from Switch_Register_Manager import CustomConsole
import sys, os, subprocess, time
import argparse, threading

from timeit import default_timer as timer

from scapy.all import *
from scapy.layers.inet import UDP, IP
from scapy.layers.l2 import Ether

currentdir = os.path.dirname(os.path.realpath(__file__))
parentdir = os.path.dirname(currentdir)
sys.path.append(parentdir)

from packet_sender import Raft
from packet_sender import DUMMY_IP_FOR_RAFT, COMMANDS


class Measurer(object):
    def __init__(self, args):
        self.console = CustomConsole(9090)
        self.socket = conf.L2socket(iface=conf.iface)
        self.packet_count = 1000
        self.total = 10000
        self._python_version = sys.version_info[0]
        self.logIndex_reader = threading.Thread(target=timed_reader, args=(self.console, ))
        self.logIndex_reader.setDaemon(True)

        if args.generator:
            self.mininet_packet_sender()

        if args.mininet:
            self.packet_sender()

        if args.reader:
            self.logIndex_reader.start()


    def mininet_packet_sender(self):
        print("starting generator")
        if self._python_version == 3:
            return subprocess.Popen(['./utils/mininet/m', 'h1', 'python3' ,'utils/performance_measures.py', '-m'],
             #stdin=subprocess.PIPE,
             #stdout=subprocess.PIPE, 
             encoding='utf-8',
             shell=False
               )


    def communicate(self, command):
        return self.console.communicate(command)

    def packet_sender(self):
        total_packet_sent = 0
        while total_packet_sent <= self.total:
            counter = 0
            message = Raft.raft_packet(
                    sourceID=0x0,
                    destinationID=1,
                    logIndex=0,
                    srcIP='10.0.1.1',
                    dstIP=DUMMY_IP_FOR_RAFT,
                    currentTerm=0,
                    messageType=COMMANDS['NewRequest'],
                    data = 1
                )
            #while counter <= self.packet_count:
            #time.sleep(0.0004)
            self.socket.send(message)
            counter += 1

            #total_packet_sent += counter
            #time.sleep(2)

def timed_reader(console):
    starting_delta = 0.1 # seconds
    result = None
    while True:
        delta = starting_delta
        start = timer()
        result = console.communicate("register_read logIndexRegister 0")
        result = result.replace('logIndexRegister[0]= ', '')
        result = int(result)
        end = timer() - start
        delta = abs(delta - end)
        print("result: {}".format(result))
        print("time: {}".format(timer()))
        time.sleep(delta)

def main():
    parser = argparse.ArgumentParser(description='Raft Packet Sender')
    parser.add_argument(
        '-g', '--generator', help='start the packet generator', required=False, action='store_true'
    )
    parser.add_argument(
        '-r', '--reader', help='start the logIndexRegister reader', required=False, action='store_true'
    )
    parser.add_argument(
        '-m', '--mininet', help='flag to know if we are within mininet', required=False, action='store_true'
    )

    args = parser.parse_args()


    m = Measurer(args=args)
    #print(m.communicate("register_read logIndexRegister 0"))
    time.sleep(60)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('\nclosing after CTRL-C')
        os._exit(0) # terminating all threads
