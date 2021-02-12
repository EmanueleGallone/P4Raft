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

#include <core.p4>
#include <v1model.p4>
#include "includes/header.p4"
#include "includes/parser.p4"

const bit<32> I2E_CLONE_SESSION_ID = 2; //clone sessions added via P4Runtime
const bit<32> E2E_CLONE_SESSION_ID = 5;

const bit<32> BMV2_V1MODEL_INSTANCE_TYPE_INGRESS_CLONE = 1;
const bit<32> BMV2_V1MODEL_INSTANCE_TYPE_EGRESS_CLONE  = 2;

const bit<32> PKT_INSTANCE_TYPE_RESUBMIT = 6;

const bit<1> TRUE = 0x1;
const bit<1> FALSE = 0x0;

#define IS_I2E_CLONE(std_meta) (std_meta.instance_type == BMV2_V1MODEL_INSTANCE_TYPE_INGRESS_CLONE)
#define IS_E2E_CLONE(std_meta) (std_meta.instance_type == BMV2_V1MODEL_INSTANCE_TYPE_EGRESS_CLONE)

#define IS_STAGED_VALUE_SET(raft_meta) (raft_meta.stagedFlag == TRUE)

//every node has the associated controller linked to port 2
#define CONTROLLER_PORT 2

#define BMV2_DROP_PORT 511 


control MyIngress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {

    // RAFT DEFINITIONS
    // some definitions to ease the code readability

    #define FOLLOWER 0
    #define CANDIDATE 1
    #define LEADER 2

    #define HEARTBEAT_REQUEST      0x1
    #define APPEND_ENTRIES         0x2
    #define HEARTBEAT_RESPONSE     0x3
    #define REQUEST_VOTE           0x4
    #define POSITIVE_RESPONSE_VOTE 0x5
    #define COMMIT_VALUE           0x6
    #define APPEND_ENTRIES_REPLY   0x7
    #define RECOVER_ENTRIES        0x8
    #define COMMIT_VALUE_ACK       0x9
    #define TIMEOUT                0xA
    #define NEGATIVE_RESPONSE_VOTE 0xB
    #define REJECT_NEW_REQUEST     0XC
    #define RETRIEVE_LOG           0xD
    #define REDIRECT               0xE

    #define START_HEARTBEAT        0xFE
    #define NEW_REQUEST            0xFF

    #define RAFT_MULTICAST         0xFF

    // END RAFT DEFINITIONS

    // RAFT REGISTERS

    register<bit<MAX_DATA_SIZE>>(MAX_LOG_SIZE << 6) logValueRegister; // 2048 max values
    register<bit<MAX_LOG_SIZE>>(1) logIndexRegister;
    register<bit<MAX_TERM_SIZE>>(1) currentTermRegister;
    register<bit<MAX_DATA_SIZE>>(1) stagedValueRegister;
    register<bit<1>>(1) stagedValueFlagRegister;

    register<bit<MAX_NUMBER_OF_NODES>>(1) countLogACKRegister; // needed for counting how many nodes replied to a new Log append
    register<bit<MAX_NUMBER_OF_NODES>>(1) IDRegister; //saving my ID
    register<bit<MAX_NUMBER_OF_NODES>>(1) majorityRegister; //need to know the quorum size to reach consensus
    register<bit<MAX_NUMBER_OF_NODES>>(1) countVoteRegister; //needed for the candidate to count the votes

    register<bit<MAX_NUMBER_OF_NODES>>(1) leaderRegister; //saving the ID of the leader
    register<bit<2>>(1) roleRegister; //0 is a follower, 1 candidate, 2 leader

    // END RAFT REGISTERS

    // RAFT COUNTERS

    counter(1, CounterType.packets) commitACKCounter;

    // END RAFT COUNTERS

    action _drop() {
        mark_to_drop(standard_metadata);
        meta.raft_metadata.set_drop = TRUE;
    }

    action _clone_to_controller() {
        // used to send the unicast packets to the controller

        meta.raft_metadata.clone_at_egress_flag = TRUE;
    }

    action _spread_raft_message_to_other_nodes(){
        // This action enables the multi-hop feature. If the topology changes,
        // the s*-runtime.json file need some editing as well:
        // add the intermediate links inside the I2E_CLONE_SESSION_ID that connects the node
        // to the other nodes. 

        clone3(CloneType.I2E, I2E_CLONE_SESSION_ID, standard_metadata);
    }

    action multicast() {
        standard_metadata.mcast_grp = 1; //setting egress ports

        hdr.raft.sourceID = meta.raft_metadata.ID;
        hdr.raft.destinationID = RAFT_MULTICAST;

        hdr.ipv4.dstAddr= 0xE000FFFF; //IPV4 Multicast Address; cast in Int = 3758161919
        hdr.ipv4.srcAddr= 0xE000FFFF; //TODO FIXME

        hdr.ethernet.dstAddr = 0x01005E7FFFFF; //Ethernet multicast
    }

    action ethernet_forward(EthernetAddress dstAddr){
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
    }

    action ipv4_forward(EthernetAddress dstAddr, egressSpec_t port) {
        //setting egress port and decrease TTL
        standard_metadata.egress_spec = port;

        ethernet_forward(dstAddr);

        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    action reply(){
        //swapping Layer3 addresses
        hdr.ipv4.dstAddr = hdr.ipv4.srcAddr;
        hdr.ipv4.srcAddr = 0xE000FFFF; // putting multicast address since IP layer is not needed
        
        ipv4_forward(hdr.ethernet.srcAddr, standard_metadata.ingress_port);

        hdr.raft.destinationID = hdr.raft.sourceID;
        hdr.raft.sourceID = meta.raft_metadata.ID;
    }

    // START RAFT ACTIONS

    action raft_forward(egressSpec_t port){
        standard_metadata.egress_spec = port;
    }

    action send_to_controller(){
        standard_metadata.egress_spec = CONTROLLER_PORT;

        hdr.raft.sourceID = meta.raft_metadata.ID;
    }

    action retrieve_log(){
        //action used to fulfill read request from client
        logValueRegister.read(hdr.raft.data, hdr.raft.logIndex);
        
        reply();
    }

    action reset_staging_area(){
        stagedValueFlagRegister.write(0, FALSE);
    }

    action leader_timeout(){
        hdr.raft.messageType = HEARTBEAT_REQUEST;

        reply();
    }

    action raft_redirect_to_leader(egressSpec_t port, IPv4Address controller_ip, bit<MAX_NUMBER_OF_NODES> destinationID){
        hdr.ipv4.dstAddr = controller_ip;

        hdr.raft.messageType = REDIRECT;

        standard_metadata.egress_spec = port;

        hdr.raft.sourceID = meta.raft_metadata.ID;
        hdr.raft.destinationID = destinationID;
    }

    action update_packet_term_and_index(){
        hdr.raft.currentTerm = meta.raft_metadata.currentTerm; //updating the currentTerm inside the packet
        hdr.raft.logIndex = meta.raft_metadata.logIndex; //writing the log index inside the packet
    }

    action write_new_term(bit<MAX_TERM_SIZE> newTerm){
        //updating the currentTerm
        currentTermRegister.write(0, newTerm);
        meta.raft_metadata.currentTerm = newTerm;
    }

    action read_all_raft_metadata(){
        //reading all the metadata needed to correctly perform some operations.
        //EAGER approach. TODO: Consider the LAZY approach to improve performances (reading values only when needed)
        currentTermRegister.read(meta.raft_metadata.currentTerm, 0);
        logIndexRegister.read(meta.raft_metadata.logIndex, 0);
        roleRegister.read(meta.raft_metadata.role, 0);
        IDRegister.read(meta.raft_metadata.ID, 0);
        majorityRegister.read(meta.raft_metadata.majority, 0);
        countLogACKRegister.read(meta.raft_metadata.countLogACK, 0);
        countVoteRegister.read(meta.raft_metadata.countVote, 0);
        leaderRegister.read(meta.raft_metadata.leaderID, 0);
        stagedValueFlagRegister.read(meta.raft_metadata.stagedFlag, 0);
    }

    action leader_CountCommitACK(){
        //counter here?
        commitACKCounter.count(0);
    }

    action leader_spread_heartbeats(){
        // received a command from controller to start sending hearbeat messages to all of the followers.
        hdr.raft.messageType = HEARTBEAT_REQUEST; //HeartBeat request

        hdr.raft.sourceID = meta.raft_metadata.ID; //putting my id
        hdr.raft.destinationID = RAFT_MULTICAST;

        update_packet_term_and_index();

        logValueRegister.read(hdr.raft.data, meta.raft_metadata.logIndex); //last log entry

        multicast();
    }

    action leader_recovery_message(){
        //this action is fired when a follower replies to an Heartbeat message with a log index
        // different than the one of the leader. In this case, the leader sends back a recovery message.

        logValueRegister.read(hdr.raft.data, hdr.raft.logIndex); // updating the new value inside follower
        hdr.raft.logIndex = hdr.raft.logIndex;

        hdr.raft.messageType = RECOVER_ENTRIES; //recoverEntries

        reply();
    }

    action leader_check_if_possible_to_commit(){
        meta.raft_metadata.countLogACK = meta.raft_metadata.countLogACK + 1;
        countLogACKRegister.write(0, meta.raft_metadata.countLogACK); //updating the counter of logACK from other nodes

        //stagedValueFlagRegister.read(meta.raft_metadata.stagedFlag, 0);
    }

    action leader_commit_value(){
        // saving the new value inside the log

        logValueRegister.write(meta.raft_metadata.logIndex, hdr.raft.data); //updating Log
        meta.raft_metadata.logIndex = meta.raft_metadata.logIndex + 1; //updating log index
        logIndexRegister.write(0, meta.raft_metadata.logIndex);
        
        hdr.raft.sourceID = meta.raft_metadata.ID;
        hdr.raft.messageType = COMMIT_VALUE; //commit value

        //stagedValueRegister.read(hdr.raft.data, 0);
        stagedValueRegister.write(0,0); //resetting staging area
        stagedValueFlagRegister.write(0, FALSE);

        multicast();
    }

    action leader_step_down(){
        //found other node that is leader
        meta.raft_metadata.role = FOLLOWER;
        roleRegister.write(0, FOLLOWER); //setting role as follower

        _clone_to_controller();
    }

    action spread_new_request() {
        //new request arrived from controller

        //staging new value
        stagedValueRegister.write(0, hdr.raft.data); //write(index, value)
        stagedValueFlagRegister.write(0, TRUE);

        hdr.raft.sourceID = meta.raft_metadata.ID;
        hdr.raft.messageType = APPEND_ENTRIES;

        multicast();    
    }

    action reject_new_request() {
        // node is in transaction for appending a new request;
        // rejecting every new request until transaction is complete.
        hdr.raft.messageType = REJECT_NEW_REQUEST;

        send_to_controller();
    }

    action candidate_start_election(){
        // TERM UPDATE MOVED TO CONTROLLER
        // meta.raft_metadata.currentTerm = meta.raft_metadata.currentTerm + 1;
        // currentTermRegister.write(0, meta.raft_metadata.currentTerm); //updating the term

        countVoteRegister.write(0, 0); //resetting the count vote

        hdr.raft.messageType = REQUEST_VOTE; //vote request

        update_packet_term_and_index();

        multicast();
    }

    action candidate_countVote(){
        meta.raft_metadata.countVote = meta.raft_metadata.countVote + 1;
        countVoteRegister.write(0, meta.raft_metadata.countVote);

        _drop(); //drop packet once used
    }

    action candidate_becomesLeader(){
        leaderRegister.write(0, meta.raft_metadata.ID);

        meta.raft_metadata.role = LEADER;
        roleRegister.write(0, LEADER);
        countVoteRegister.write(0, 0); //resetting the vote count
    }

    action follower_handle_heartbeat() {
        _spread_raft_message_to_other_nodes(); //perform Clone I2E for letting the other nodes that a Hearbeat Request has arrived

        leaderRegister.write(0, hdr.raft.sourceID); //at this point we know that the node is the leader

        logValueRegister.read(hdr.raft.data, meta.raft_metadata.logIndex); //placing last entry of follower's log

        hdr.raft.messageType = HEARTBEAT_RESPONSE;
        update_packet_term_and_index();
   
        reply();
        _clone_to_controller();
    }

    action candidate_becomesFollower(){
        meta.raft_metadata.role = FOLLOWER;
        roleRegister.write(0, FOLLOWER);
        countVoteRegister.write(0, 0); //resetting the vote count

        follower_handle_heartbeat();
    }

    action follower_handle_log_replication(){
        _spread_raft_message_to_other_nodes();

        hdr.raft.messageType = APPEND_ENTRIES_REPLY; // follower replies with AppendEntriesReply

        update_packet_term_and_index();

        _clone_to_controller();

        reply();
    }

    action candidate_becomesFollowerAndLog(){
        candidate_becomesFollower();

        follower_handle_log_replication();
    }

    action follower_commit_value(){
        //leader has consolidated the new value. Follower now must consolidate it too.
        _spread_raft_message_to_other_nodes();

        logValueRegister.write(meta.raft_metadata.logIndex, hdr.raft.data);
        logIndexRegister.write(0, meta.raft_metadata.logIndex + 1);

        meta.raft_metadata.logIndex = meta.raft_metadata.logIndex + 1; //maybe useless

        // replying with ACK
        hdr.raft.messageType = COMMIT_VALUE_ACK; //CommitValueACK

        update_packet_term_and_index();

        reply();
    }

    action follower_timeout(){
        //controller sent a timeout message. Changing role to candidate and starting the election process

        meta.raft_metadata.role = CANDIDATE; //changing status to candidate
        roleRegister.write(0, CANDIDATE);

        candidate_start_election();
    }

    action positive_vote_reply(){
        hdr.raft.messageType = POSITIVE_RESPONSE_VOTE; //vote reply

        update_packet_term_and_index();

        reply();
    }

    action negative_vote_reply(){
        hdr.raft.messageType = NEGATIVE_RESPONSE_VOTE; //vote reply

        update_packet_term_and_index();

        reply();
    }

    action follower_handle_recovery_message(){
        
        logValueRegister.write(hdr.raft.logIndex, hdr.raft.data);
        logIndexRegister.write(0, hdr.raft.logIndex + 1);
        meta.raft_metadata.logIndex = meta.raft_metadata.logIndex + 1;

        _drop(); //simply drop the recovery packet once used
    }

    // END RAFT ACTIONS

    table ipv4_lpm { //ipv4 longest prefix
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            _drop;
            NoAction;
        }
        size = 512;
        default_action = NoAction();
    }

    // START RAFT TABLES
    
    table leader{
        key = {
                hdr.raft.messageType: exact;
                standard_metadata.ingress_port: exact; //ternary is not used since has an impact on performances
            }
        actions = {
            leader_CountCommitACK;
            leader_spread_heartbeats;
            leader_step_down;
            spread_new_request;
            leader_timeout;
            _drop;
            NoAction;
        }
        
        //vote messages must be handled in apply section, below

        default_action = NoAction();
        const entries = {
            (HEARTBEAT_REQUEST, 3) : leader_step_down(); //received HeartBeat from Leader
            (HEARTBEAT_REQUEST, 4) : leader_step_down(); //received HeartBeat from Leader
            (APPEND_ENTRIES, 3) : leader_CountCommitACK();
            (APPEND_ENTRIES, 4) : leader_CountCommitACK();
            (TIMEOUT, CONTROLLER_PORT) : leader_timeout(); // informing controller that node is already leader.
            (START_HEARTBEAT, CONTROLLER_PORT) : leader_spread_heartbeats();
            (NEW_REQUEST, CONTROLLER_PORT) : spread_new_request(); //received NewRequest from controller. NoAction    
            (HEARTBEAT_RESPONSE, 3): _drop();
            (HEARTBEAT_RESPONSE, 4): _drop();      
        }
    }

    table candidate {
        key = { 
            hdr.raft.messageType: exact;
            standard_metadata.ingress_port: exact; //ternary not used.
        }
        actions = {
            candidate_start_election;
            candidate_countVote;
            candidate_becomesLeader;
            candidate_becomesFollowerAndLog;
            candidate_becomesFollower;
            follower_handle_heartbeat;
            _drop;
            NoAction;
        }
        default_action = NoAction();

        const entries = {   
            (HEARTBEAT_REQUEST, 3) : candidate_becomesFollower(); //received HeartBeat from Leader
            (HEARTBEAT_REQUEST, 4) : candidate_becomesFollower(); //received HeartBeat from Leader
            (APPEND_ENTRIES, 3) : candidate_becomesFollowerAndLog(); //received AppendEntries from Leader. step down to Follower status
            (APPEND_ENTRIES, 4) : candidate_becomesFollowerAndLog(); //received AppendEntries from Leader. step down to Follower status
            (POSITIVE_RESPONSE_VOTE, 3) : candidate_countVote(); //received a positive vote
            (POSITIVE_RESPONSE_VOTE, 4) : candidate_countVote(); //received a positive vote
            (NEGATIVE_RESPONSE_VOTE, 3) : NoAction(); //received a negative_vote.
            (NEGATIVE_RESPONSE_VOTE, 4) : NoAction(); //received a negative_vote.
            (TIMEOUT, CONTROLLER_PORT) : candidate_start_election(); //received timeout from controller. starting election
            (NEW_REQUEST, 3) : NoAction(); //received NewRequest from controller. NoAction. Will perform redirect if leader is elected
            (NEW_REQUEST, 4) : NoAction(); //received NewRequest from controller. NoAction. Will perform redirect if leader is elected        
        }
    }

    table follower {
        key = { 
            meta.raft_metadata.role: exact;
            hdr.raft.messageType: exact;
            hdr.raft.destinationID: exact;
        }
        actions = {
            follower_handle_log_replication;
            follower_handle_heartbeat;
            follower_commit_value;
            follower_timeout;
            follower_handle_recovery_message;
            _drop;
            NoAction;
        }
        size = 64;
        default_action = NoAction();

        //vote messages must be handled in apply section, below
        //entries from P4Runtime. Open config/s*-runtime.json to see table's entries

        // CONST ENTRIES OF NODE 1 TO EASE READABILITY.
        /*
        const entries = {
            (FOLLOWER, HEARTBEAT_REQUEST, RAFT_MULTICAST) : follower_handle_heartbeat(); //received HeartBeat from Leader
            (FOLLOWER, APPEND_ENTRIES, RAFT_MULTICAST) : follower_handle_log_replication(); //received AppendEntries from Leader.
            (FOLLOWER, TIMEOUT, 1) : follower_timeout(); //received timeout from controller. starting election
            (FOLLOWER, RECOVER_ENTRIES, 1) : follower_handle_recovery_message(); //received recovery from leader. recover entry            
        }
        */
    }

    table raft_redirect {
        // this table is needed in case a new request from external client
        // reach a node that is not a leader.
        // It will redirect the new request to the leader node's controller
        key = { 
            meta.raft_metadata.role: exact;
            meta.raft_metadata.leaderID: exact;
            hdr.raft.messageType: exact;
        }
        actions = {
            raft_forward;
            raft_redirect_to_leader;
            multicast;
            _drop;
            NoAction;
        }
        size = 64;
        default_action = NoAction();
    }

    table raft_forwarding {
        key = { 
            hdr.raft.destinationID: exact;
        }
        actions = {
            raft_forward;
            multicast;
            _drop;
            NoAction;
        }
        size = 64;
        default_action = NoAction();

        //entries from P4Runtime. Open config/s*-runtime.json to see table's entries
    }

    // END RAFT TABLES

    table dbg_raft_table{
        key = {
            standard_metadata.ingress_port : exact;
            standard_metadata.egress_spec : exact;
            standard_metadata.egress_port : exact;
            standard_metadata.instance_type : exact;
            standard_metadata.packet_length : exact;
            standard_metadata.mcast_grp : exact;
            standard_metadata.egress_rid : exact;
            standard_metadata.enq_qdepth: exact;
            standard_metadata.deq_qdepth: exact;
            standard_metadata.ingress_global_timestamp: exact;
            hdr.raft.sourceID: exact;
            hdr.raft.destinationID: exact; 
            hdr.raft.logIndex: exact; 
            hdr.raft.currentTerm: exact; 
            hdr.raft.data: exact;        
            hdr.raft.messageType: exact;
        }
        actions = { NoAction; }
        const default_action = NoAction();     
    }

    apply { 
        // All the Raft logic that cannot be handled with the paradigm Match-Action is handled here
        
            if (hdr.ipv4.isValid()) { //Layer 3 handling
                ipv4_lpm.apply();
            }



            if (hdr.raft.isValid()) { //check if it's a Raft Packet
            // BEGIN RAFT PREAMBLE

                //dbg_raft_table.apply(); // debug
                
                read_all_raft_metadata();                
		
        		if (hdr.raft.messageType == RETRIEVE_LOG){
        			//read log logic. Client can read only valid data from log.
        			if (hdr.raft.logIndex <= meta.raft_metadata.logIndex){
        				retrieve_log();
        				exit;
        			}
        			else {
        			    _drop();
        			    exit;
        			}
        		} // end of if (messageType == RETRIEVE_LOG)
		
                if (hdr.raft.messageType == NEW_REQUEST) {
                    hdr.raft.currentTerm = meta.raft_metadata.currentTerm; // making new request from clients don't care about the term
                    raft_redirect.apply();

                    if(IS_STAGED_VALUE_SET(meta.raft_metadata)) { // check if node is in transaction mode
                        reject_new_request();
                        exit; // ending the pipeline
                    }
                }
                

                if ( hdr.raft.currentTerm < meta.raft_metadata.currentTerm ){ //drop all outdated packets
                    _drop();
                    exit;
                }

                //end RAFT PREAMBLE


                if (hdr.raft.currentTerm >= meta.raft_metadata.currentTerm){
                    write_new_term(hdr.raft.currentTerm);

                    raft_forwarding.apply(); //overwriting ip forwarding

                    if (meta.raft_metadata.role == LEADER){ //checking if node is leader
                        leader.apply();

                        if (hdr.raft.messageType == APPEND_ENTRIES_REPLY){ //AppendEntriesReply handling.

                            leader_check_if_possible_to_commit();

                            if (meta.raft_metadata.countLogACK >= (meta.raft_metadata.majority - 1) && (IS_STAGED_VALUE_SET(meta.raft_metadata))){
                                //under these conditions, the leader can commit the value and resetting the counters

                                meta.raft_metadata.countLogACK = 0;
                                countLogACKRegister.write(0, 0); //resetting the counter.

                                leader_commit_value();
                            }

                            else if(!IS_STAGED_VALUE_SET(meta.raft_metadata)){
                                //received an AppendEntriesReply but value is already committed, perform No Action
                                countLogACKRegister.write(0,0); //needed because otherwise the ACK from the old commit will remain saved.
                                meta.raft_metadata.countLogACK = 0;

                                _drop();
                                exit;
                            }
                        }

                        if (hdr.raft.messageType == HEARTBEAT_RESPONSE){ //HeartBeat Response
                            if(hdr.raft.logIndex < meta.raft_metadata.logIndex) //follower is behind with the log. send a recovery message
                                
                                leader_recovery_message();
                        }

                        if (hdr.raft.messageType == REQUEST_VOTE){
                            _spread_raft_message_to_other_nodes();

                            //need to perform some checks before replying with my vote
                            if (hdr.raft.logIndex >= meta.raft_metadata.logIndex){
                                leader_step_down();
                                positive_vote_reply();
                            }
                        }
                    } //end if (meta.raft_metadata.role == LEADER)

                    if (meta.raft_metadata.role == CANDIDATE){
                        candidate.apply();

                        if(hdr.raft.messageType == POSITIVE_RESPONSE_VOTE && meta.raft_metadata.countVote >= (meta.raft_metadata.majority -1)){
                            //means that we reached the quorum -> can become Leader
                            candidate_becomesLeader(); //changing state
                            leader_spread_heartbeats(); //this action will inform the controller that the node became leader 
                        }
                        
                    }

                    if (meta.raft_metadata.role == FOLLOWER){
                        follower.apply();

                            if (hdr.raft.messageType == REQUEST_VOTE && hdr.raft.sourceID != meta.raft_metadata.ID){ //request vote handling
                                _spread_raft_message_to_other_nodes();

                                if (hdr.raft.logIndex >= meta.raft_metadata.logIndex)
                                    positive_vote_reply();
                                else
                                    negative_vote_reply();
                            }

                    } // end if (meta.raft_metadata.role == FOLLOWER)

                } //end of if (hdr.raft.currentTerm >= meta.raft_metadata.currentTerm)

            } // end of if (hdr.raft.isValid())

    } // end of apply{} section

} //end of MyIngress

//////////////////EGRESS////////////////////////////////

control MyEgress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {

    counter(1, CounterType.packets) egressRaftCounter;
    counter(1, CounterType.packets) appendEntriesCounter;
    counter(1, CounterType.packets) newRequestCounter;
    counter(1, CounterType.packets) rejectNewRequestCounter;

    action _drop() {
        mark_to_drop(standard_metadata);
    }

    //TODO Assign IP to Egress Ports

    action _clone() {
    	clone(CloneType.E2E, E2E_CLONE_SESSION_ID);
    }

    table dbg_raft_table{
        key = {
            standard_metadata.ingress_port : exact;
            standard_metadata.egress_spec : exact;
            standard_metadata.egress_port : exact;
            standard_metadata.instance_type : exact;
            standard_metadata.packet_length : exact;
            standard_metadata.mcast_grp : exact;
            standard_metadata.egress_rid : exact;
            standard_metadata.enq_qdepth: exact;
            standard_metadata.deq_qdepth: exact;
            standard_metadata.egress_global_timestamp: exact;
            hdr.ipv4.srcAddr: exact;
            hdr.ipv4.dstAddr: exact;
            hdr.raft.sourceID: exact;
            hdr.raft.destinationID: exact; 
            hdr.raft.logIndex: exact; 
            hdr.raft.currentTerm: exact; 
            hdr.raft.data: exact;        
            hdr.raft.messageType: exact;

        }
        actions = { NoAction; }
        const default_action = NoAction();     
    }

    apply {
        if (hdr.ipv4.isValid()){

        }

        if (hdr.raft.isValid()){
            egressRaftCounter.count(0);

            if (hdr.raft.messageType == APPEND_ENTRIES){ //TODO: make a table out of these IFs
                appendEntriesCounter.count(0);
            }
            if (hdr.raft.messageType == NEW_REQUEST){
                newRequestCounter.count(0);
            }
            if (hdr.raft.messageType == REJECT_NEW_REQUEST){
                rejectNewRequestCounter.count(0);
            }

            if (meta.raft_metadata.clone_at_egress_flag == TRUE){
                _clone();
                meta.raft_metadata.clone_at_egress_flag = FALSE; // may be useless
            }

            if (IS_I2E_CLONE(standard_metadata)){ //spreading messages to other nodes
                if (standard_metadata.egress_port == standard_metadata.ingress_port) 
                    _drop(); // Prune multicast packet to ingress port to prevent looping
            }

            //dbg_raft_table.apply(); //debug

        } //end of if (hdr.raft.isValid())
    } // end of apply{}
}

/////////////////////////SWITCH/////////////////////////

V1Switch(TopParser(), verifyChecksum(), MyIngress(), MyEgress(), computeChecksum(), TopDeparser()) main;
