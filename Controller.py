from scapy.all import *
from packet_sender import Raft, send_no_reply, COMMANDS
from threading import Event
from utils.Switch_Register_Manager import CustomConsole
from timeit import default_timer as timer

import argparse

RANDOM_TIMEOUT = {'min': 150, 'max': 300}  # min max values in ms
RAFT_HEARTBEAT_RATE = 50
STATUSES = {'follower': 0, 'candidate': 1, 'leader': 2}
RAFT_PROTOCOL_DSTPORT = 0x9998
IP_MULTICAST_ADDRESS = '224.0.255.255'

#logging_format = '%(asctime)-15s [%(threadName)s] - [%(funcName)s] %(message)s'
logging_format = ''
level = logging.ERROR  # Change to Error or something like that to silence the log to file!
logging.basicConfig(filename='./logs/controller.log', level=level, format=logging_format)
logger = logging.getLogger()



class Controller(object):
    def __init__(self, controller_ip):
        self.status = STATUSES['follower']
        self.timeout_thread = None
        self.controller_ip = controller_ip
        self.nodeID = args.ID # the controllee raft node
        self.term = 0
        self.logIndex = 0
        self.counter_new_request = 0
        self.counter_rejected_requests = 0
        self.sniffer = AsyncSniffer(
            iface=conf.iface,
            lfilter=is_ingoing_raft_packet,
            prn=lambda _pkt: self.handle_packet(_pkt)
            )
        self.sniffer.start()

        self.heartbeat_loop_thread = threading.Thread(target=self.heartbeats_loop)
        self.heartbeat_loop_thread.start()
        self.time = None
        self.stop_flag = Event()

        if self.nodeID == 1:
            self.failure_thread = threading.Thread(target=self.emulate_failure)
            self.failure_thread.start()

        self.init_timeout()  # starting as follower, we need to start the timeout


    def handle_packet(self, packet):
        if packet[Raft].messageType == COMMANDS['RequestVote'] and packet[Raft].sourceID == self.nodeID:
            self.status = STATUSES['candidate']
            self.time = timer()
            print('vote request: -> state: {};'.format(self.status))

        if packet[Raft].messageType == COMMANDS['HeartBeatRequest'] and packet[Raft].sourceID == self.nodeID:  # received the heartbeat from node -> node has won the election
            if self.status == STATUSES['candidate']:
                print('won election -> status = leader')
                print('time elapsed (in ms): {}'.format((timer() - self.time)*1000))
                logger.debug('[nodeID: {}] won election: {}'.format(self.nodeID, timer()))
                print('election absolute time: {}'.format(timer()))

            self.status = STATUSES['leader']
            self.term = packet[Raft].currentTerm
            self.logIndex = packet[Raft].logIndex

        if packet[Raft].messageType == COMMANDS['HeartBeatRequest'] and not packet[Raft].sourceID == self.nodeID:
            self.status = STATUSES['follower']
            self.term = packet[Raft].currentTerm
            self.logIndex = packet[Raft].logIndex

            self.init_timeout()

        if packet[Raft].messageType == COMMANDS['HeartBeatResponse']:  # received a cloned heartbeat response from node -> reset timeout
            #print('resetting timeout; response to destinationID: {}'.format(packet[Raft].destinationID))
            #print('state : {}'.format(self.status))
            self.term = packet[Raft].currentTerm

            if self.status == STATUSES['leader']:
                print('stepping down as leader.')
                self.status = STATUSES['follower']

            self.init_timeout()

        if packet[Raft].messageType == COMMANDS['AppendEntriesReply']:  # received a cloned AppendEntries response from node -> reset timeout
            #print('resetting timeout; AppendEntries from: {}'.format(packet[Raft].destinationID))
            #print('state : {}'.format(self.status))

            self.term = packet[Raft].currentTerm
            self.logIndex = packet[Raft].logIndex

            self.init_timeout()

        # if packet[Raft].messageType == COMMANDS['AppendEntries']:
        #     print('starting Transaction: {}'.format(time.time()))

        if packet[Raft].messageType == COMMANDS['Redirect'] and self.status == STATUSES['leader']:
            # received a redirected New Request from a client
            # new request can be made only by controllers
            self.counter_new_request += 1
            packet[Raft].messageType = COMMANDS['NewRequest']

            logger.debug('[nodeID: {}] redirected New Request received; total: {}; time: {}'.format(
                self.nodeID,
                self.counter_new_request,
                timer())
            )
            #print('New Request received; total: {}; time: {}'.format(self.counter_new_request, time.time()))

            packet[Raft].sourceID = 0x0
            packet[Raft].destinationID = self.nodeID
            packet[IP].srcAddr = args.source
            #packet[Raft].show()
            send_no_reply(packet)

            #if (self.counter_new_request % 1000 == 0) and self.nodeID == 1:  # emulating failure                self.sniffer.start():
                #self.emulate_failure()

        if packet[Raft].messageType == COMMANDS['RejectNewRequest']:
            self.counter_rejected_requests += 1
            logger.debug('[nodeID: {}] New request rejected; total {}'.format(self.nodeID, self.counter_rejected_requests))
            #print('New request rejected; total {}'.format(self.counter_rejected_requests))

            #print('state : {}'.format(self.status))

        # if packet[Raft].messageType == COMMANDS['CommitValue']:
        #     print('Transaction complete. time: {}'.format(time.time()))
            #print('send confirmation to Client')

        # if packet[Raft].messageType == COMMANDS['RetrieveLog']:
        #     print('retrieved value: {} at index: {}'.format(packet[Raft].data, packet[Raft].logIndex))
        #logger.debug(packet.sprintf())

        #packet[Raft].show()

    def emulate_failure(self):
        #cmd = CustomConsole(9090)
        time.sleep(10)
        #cmd.communicate("register_write roleRegister 0 0")
        logger.debug('[nodeID: {}] failure time: {}'.format(self.nodeID, timer()))
        print('failure time: {}'.format(timer()))
        self.sniffer.stop(join=False)
        self.stop_flag.set()
        time.sleep(5)
        self.sniffer.start()
        self.stop_flag.clear()
        # import os
        # print('emulating failure after {} New Req>
        # os._exit(0)

    def raft_timeout(self):
        return random.randrange(RANDOM_TIMEOUT['min'], RANDOM_TIMEOUT['max']) / 1000

    def reset_timeout(self):
        self.election_time = time.time() + self.raft_timeout()

    def init_timeout(self):
        self.reset_timeout()
        # safety guarantee, timeout thread may expire after election
        if self.timeout_thread and self.timeout_thread.is_alive():
            return
        self.timeout_thread = threading.Thread(target=self.timeout_loop)
        self.timeout_thread.start()

    def heartbeats_loop(self):
        rate = RAFT_HEARTBEAT_RATE / 1000
        while True:  # todo find a way to block this thread in a more clever way
            if self.status == STATUSES['leader'] and not self.stop_flag.is_set():
                #print('sending StartHeartbeat')
                self.send_heartbeat_request()
                time.sleep(rate)
            else:
                time.sleep(rate)
        return

    # the timeout function
    def timeout_loop(self):
        # only stop timeout thread when winning the election
        while self.status != STATUSES['leader']:

            delta = self.election_time - time.time()
            if delta < 0:
                self.start_election()
                self.reset_timeout()
            else:
                time.sleep(delta)
        return


    def start_election(self):
        print('starting election')
        #logger.debug("{} starting election; status: {}, term:{}".format(self.controller_ip, self.status, self.term))
        self.term += 1
        start_election_message = Raft.raft_packet(
                sourceID=0x0,
                destinationID=self.nodeID,
                data=0x0,
                logIndex=self.logIndex,
                srcIP=args.source,
                dstIP=IP_MULTICAST_ADDRESS,
                currentTerm=self.term,
                messageType=COMMANDS['Timeout']
            )

        send_no_reply(start_election_message)

    def send_heartbeat_request(self):
        #print("Sending heartbeat request")
        #logger.debug("Starting HEARTBEATS")

        heartbeat = Raft.raft_packet(
                sourceID=0x0,
                destinationID=self.nodeID,
                data=0x0,
                logIndex=self.logIndex,
                srcIP=args.source,
                dstIP=IP_MULTICAST_ADDRESS,
                currentTerm=self.term,
                messageType=COMMANDS['StartHeartbeat']
            )

        send_no_reply(heartbeat)


# def main_handle_packet(packet): 
#     packet[Raft].show()

def is_ingoing_raft_packet(_packet):
    if _packet.haslayer(IP):
        if not _packet[IP].proto == 'icmp':
            if _packet.haslayer(UDP):
                if _packet[UDP].dport == RAFT_PROTOCOL_DSTPORT:
                    if _packet.haslayer(Raft):
                       #return True
                        if _packet[Raft].sourceID != 0x0:
                            return True
    return False

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Raft Packet Sender')
    parser.add_argument(
        '-s', '--source', help='select the node IP (default=10.0.1.1)', default='10.0.1.1', required=False,
        type=str
    )
    parser.add_argument(
        '-i', '--ID', help='ID of raft node', default='1', required=False,
        type=int
    )
    args = parser.parse_args()

    controller = Controller(args.source)
    print('starting controller')

    while True:  # useless, only to keep the main thread alive
        time.sleep(10)
