
![Generic badge](https://img.shields.io/badge/PythonVersions-3.8-green.svg)

[NOT UPDATED]

# Introduction
RaftP4 is a dataplane-layer implementation of Raft's Consensus algorithm that
uses UDP segments, crafted using Scapy 2.4.2 (see references).
This implementation provides the following features:
* leader election
* log replication
* node recovery (under some specific circumstances)

# Getting started
download and run the VM of [P4lang](https://www.github.com/p4lang/tutorials) (it's the fastest way to get a working environment).

This project relies on [Mininet](http://mininet.org), using P4's BMV2 switches.
The topology is described in **topology.png**

When ready, navigate to the cloned/downloaded folder of this project, open a shell and run:
```
make run
```
at this point, you should see the Mininet shell.

## Running the application
open another terminal and type:
```
python Switch_Register_Manager.py -a
```
This will set the correct parameters to run Raft inside P4 devices. 

inside mininet prompt, run 
```
xterm h1 h2 h3
```
to open the emulated hosts' terminal. H1 will be the controller.

![til](docu/opening_mininet.gif)

on h1 terminal type
```
python packet_sender.py --command 0xA --term 0 --destination 10.0.1.254
```
parameters:
* --command (-c) : is the messageType that will be sent to the device specified (full list of message types is inside the **packet_sender.py** script).
* -- term (-t) : is the Raft term (Be careful, in the actual status, if the term is less than the term inside the devices, the packet will be dropped).
* --destination (-d) : IP destination on whom to send the packet. 

## Value Consensus
Send a timeout packet to one of the devices (**--command 0xA** or in Int format **--command 10**)

e.g.: in another terminal: 
```
python packet_sender --command 0xA -d 10.0.1.254 -t 0
```

Use now the Switch_Register_Manager.py tool to verify that the node who performed the timeout is the actual leader:

```
python Switch_Register_Manager.py -ra --port 9090
```
# Useful mininet commands
example to bring down a link, type inside the mininet shell
```
sh ifconfig s1-eth1 down
```

# Improvements

# Troubleshooting
* if you have errors by running the application, most probably you have to check inside the makefile
and fix the path of BMV2 and P4C
* If mininet shows an error like **Error creating interface pair: RTNETLINK answers: File exists** on start, try 'make stop' and then again 'make run'

# Known Issues

# Warnings
* 0 (0x0) value is not supported
* not yet tested outside mininet

# References
[Raft](https://raft.github.io/) <br>
[Scapy](https://scapy.net/) <br>
[P4](https://p4.org) <br>
