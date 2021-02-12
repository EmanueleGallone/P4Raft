/*
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
*/

#ifndef _HEADERS_P4_
#define _HEADERS_P4_

typedef bit<48> EthernetAddress;
typedef bit<32> IPv4Address;
typedef bit<4> PortId;
typedef bit<8> Byte_t;

typedef bit<9>  egressSpec_t;

// Physical Ports
const PortId DROP_PORT = 0xF;

// standard headers
header ethernet_t {
    EthernetAddress dstAddr;
    EthernetAddress srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4> version;
    bit<4> ihl;
    bit<8> diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3> flags;
    bit<13> fragOffset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdrChecksum;
    IPv4Address srcAddr;
    IPv4Address dstAddr;
}

header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length_;
    bit<16> checksum;
}

// Headers for Raft
// NB: If you change bit sizes here remember to change also in raft_definitions.py the type of field inside the packet crafter!!!!
#define BOOLEAN 8
#define BYTE 8
#define MAX_DATA_SIZE 64
#define MAX_LOG_SIZE 32
#define MAX_TERM_SIZE 32
#define MAX_NUMBER_OF_NODES 16

header raft_t {
    //NB: map the header definition inside the packet crafter!

    Byte_t type_sourceID;
    Byte_t length_sourceID;
    bit<MAX_NUMBER_OF_NODES> sourceID;       // ID of the source node
    Byte_t type_destinationID;
    Byte_t length_destinationID;
    bit<MAX_NUMBER_OF_NODES> destinationID; // ID of the destination Node
    Byte_t type_logIndex;
    Byte_t length_logIndex;
    bit<MAX_LOG_SIZE> logIndex;            // index of the last entry on Leader's log
    Byte_t type_currentTerm;
    Byte_t length_currentTerm;
    bit<MAX_TERM_SIZE> currentTerm;        // or Epoch
    Byte_t type_data;
    Byte_t length_data;
    bit<MAX_DATA_SIZE> data;               // actual value to be pushed inside the log 
    Byte_t type_messageType;
    Byte_t length_messageType;        
    bit<BYTE> messageType;                 // represents the command
    bit<BYTE> version;                     // protocol version
}

struct headers {
    ethernet_t ethernet;
    ipv4_t ipv4;
    udp_t udp;
    raft_t raft;
}

struct raft_metadata_t {
    bit<1> set_drop;
    bit<1> clone_at_egress_flag;
    bit<MAX_TERM_SIZE> currentTerm;
    bit<MAX_LOG_SIZE> logIndex;
    bit<1> stagedFlag;
    bit<2> role; // max 3 roles: follower, candidate, leader
    bit<MAX_NUMBER_OF_NODES> ID;
    bit<MAX_NUMBER_OF_NODES> majority;
    bit<MAX_NUMBER_OF_NODES> countLogACK;
    bit<MAX_NUMBER_OF_NODES> countVote;
    bit<MAX_NUMBER_OF_NODES> leaderID;

}

struct metadata {
    raft_metadata_t   raft_metadata;
}

#endif
