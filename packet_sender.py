#!/usr/bin/env python3

# Compatible also with Python2.7
'''
Author Emanuele Gallone
Date 08/2020

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
'''

from threading import Thread, Event
from scapy.all import *
from scapy.layers.inet import UDP, IP
from scapy.layers.l2 import Ether

import time
from timeit import default_timer as timer
import argparse
import random

class Raft(Packet):
    name = "RaftPacket "
    fields_desc = [
    	XByteField("type_sourceID", 0x0),
    	XByteField("length_sourceID", 0x16),
        XShortField("sourceID", 0x0),  # defined as 'field(name, default_value)'
    	XByteField("type_destinationID", 0x0),
    	XByteField("length_destinationID", 0x16),
        XShortField("destinationID", 0x0),
    	XByteField("type_logIndex", 0x0),
    	XByteField("length_logIndex", 0x32),
        XIntField("logIndex", 0x0),
    	XByteField("type_currentTerm", 0x0),
    	XByteField("length_currenTerm", 0x32),
        XIntField("currentTerm", 0x0),
    	XByteField("type_data", 0x0),
    	XByteField("length_data", 0x64),
        XLongField("data", 0x0),
    	XByteField("type_messageType", 0x0),
    	XByteField("length_messageType", 0x8),
        XByteField("messageType", 0x0),
        XByteField("Version", 0x0)
    ]

    def raft_packet(sourceID,
                destinationID,
                logIndex,
                currentTerm,
                data,
                srcIP,
                dstIP,
                messageType):

        """helper method to craft a Raft packet"""
        custom_mac = "08:00:27:10:a8:80"  # don't care. The switch will replace it automatically

        eth = Ether(dst=custom_mac)
        ip = IP(src=srcIP, dst=dstIP)
        udp = UDP(sport=raft_protocol_dstport, dport=raft_protocol_dstport)

        _packet = eth / ip / udp / Raft(sourceID=sourceID,
                                        destinationID=destinationID,
                                        logIndex=logIndex,
                                        currentTerm=currentTerm,
                                        data=data,
                                        messageType=messageType,
                                        Version=0x0)

        return _packet

raft_protocol_dstport = 0x9998  # raft protocol identifier on port 9998 see parser.p4

bind_layers(UDP, Raft, dport=raft_protocol_dstport)

COMMANDS = {
    'HeartBeatRequest': 0x1,
    'AppendEntries': 0x2,
    'HeartBeatResponse': 0x3,
    'RequestVote': 0x4,
    'PositiveResponseVote': 0x5,
    'CommitValue': 0x6,
    'AppendEntriesReply': 0x7,
    'RecoverEntries': 0x8,
    'CommitValueACK': 0x9,
    'Timeout': 0xA,
    'NegativeResponseVote': 0xB,
    'RejectNewRequest': 0xC,
    'RetrieveLog': 0xD,
    'Redirect': 0xE,
    'StartHeartbeat': 0xFE,
    'NewRequest': 0xFF
            }

DUMMY_IP_FOR_RAFT = '224.0.255.255'


def send_no_reply(message):
    sendp(message, iface=conf.iface, count=1, return_packets=False, verbose=False)


class MyThread(Thread):
    def __init__(self, event):
        Thread.__init__(self)
        self.stopped = event
        self.nodes_id_list = [1, 2, 3, 4, 5] # not used
        self.socket = conf.L2socket(iface=conf.iface)

    def run(self):
        count = 0x0
        logIndex = 0
        sleep_time = 0.1

        if args.command == COMMANDS['RetrieveLog']:
            logIndex = 1

        message = Raft.raft_packet(
                sourceID=0x0,
                destinationID=args.ID,
                data=count,
                logIndex=logIndex,
                srcIP=args.source,
                dstIP=DUMMY_IP_FOR_RAFT,
                currentTerm=args.term,
                messageType=args.command
            )

        while count < args.count:
            # call a function
            message[Raft].data = count

            self.socket.send(message)
            print("sent packet; destinationID: {}; : time: {}".format(message[Raft].destinationID, time.time()))
            count += 0x1

    def send_heartbeat(self):
        message = Raft.raft_packet(
                sourceID=0x0,
                destinationID=args.ID,
                logIndex=0,
                srcIP=args.source,
                dstIP=DUMMY_IP_FOR_RAFT,
                currentTerm=args.term,
                messageType=args.command
            )

class PacketGenerator(object):
    def __init__(self, max_num_of_packets, max_num_of_threads, command):

        self.max_num_of_threads = max_num_of_threads
        self.max_num_of_packets = max_num_of_packets // max_num_of_threads # subdivision of packet generation
        self.threads = []
        self.command = command
        self.total_time = 0
        self.socket = conf.L2socket(iface=conf.iface)

        for i in range(0, self.max_num_of_threads ):
            self.threads.append( threading.Thread(target=self._generator) )

    def _generator(self):
        counter = 0
        message = Raft.raft_packet(
                sourceID=0x0,
                destinationID=args.ID,
                logIndex=0,
                srcIP=args.source,
                dstIP=DUMMY_IP_FOR_RAFT,
                currentTerm=args.term,
                messageType=self.command,
                data = 1
            )

        start_time = timer()

        while counter < self.max_num_of_packets:
            counter += 1

            message[Raft].data = counter
            message[Raft].term = args.term
            #time.sleep(0.0004)
            #send_no_reply(message)
            self.socket.send(message)
            #print('generating packet')

        end_time = timer() - start_time
        print('total sent: {}, time : {}'.format(counter, end_time))

        return

    def start(self):
        for t in self.threads:
            t.start()

        for t in self.threads:
            t.join()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Raft Packet Sender')
    parser.add_argument(
        '-c', '--command', help='select command to send', default=0xFF, required=False,
        type=lambda x: int(x,0)
    ) # 0x2 is the AppendEntries type. see COMMANDS list in raft_definitions.py
    parser.add_argument(
        '-i', '--ID', help='select the ID of the raft node ', default=1, required=False,
        type=int
    )
    parser.add_argument(
        '-s', '--source', help='source IP (should be the IP of the controller)', default='10.0.1.1', required=False,
        type=str
    )
    parser.add_argument(
        '-t', '--term', help='select the Raft term', default=0, required=False,
        type=int
    )
    parser.add_argument(
    	'-co', '--count', help='how many packets to send', default=1, required=False, type=int
    )

    parser.add_argument(
        '-g', '--generator', help='start the packet generator', required=False, action='store_true'
    )

    args = parser.parse_args()

    if args.generator:
        gen = PacketGenerator(max_num_of_packets=1000, max_num_of_threads=1, command=COMMANDS['NewRequest'])
        gen.start()
        #time.sleep(1)
        exit()

    stop_flag = Event()
    t = MyThread(stop_flag)
    t.start()

    time.sleep(1)
    stop_flag.set()
