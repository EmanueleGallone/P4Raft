BUILD_DIR = build
PCAP_DIR = pcaps
LOG_DIR = logs

P4C = p4c-bm2-ss
P4C_ARGS += --p4runtime-files $(BUILD_DIR)/$(basename $@).p4.p4info.txt

RUN_SCRIPT = utils/run.py

BMV2_SWITCH_EXE = simple_switch_grpc

ifndef TOPO
TOPO = config/topology.json
endif

source = $(wildcard *.p4)
compiled_json := $(source:.p4=.json)

ifndef DEFAULT_PROG
# WARNING!!!
#DEFAULT_PROG = $(wildcard *.p4)
DEFAULT_PROG = $(wildcard Raft.p4)
endif
DEFAULT_JSON = $(BUILD_DIR)/$(DEFAULT_PROG:.p4=.json)

# Define NO_P4 to start BMv2 without a program
ifndef NO_P4
run_args += -j $(DEFAULT_JSON)
endif

# Set BMV2_SWITCH_EXE to override the BMv2 target
ifdef BMV2_SWITCH_EXE
run_args += -b $(BMV2_SWITCH_EXE)
endif

all: run

run: build
	sudo -E python $(RUN_SCRIPT) -t $(TOPO) $(run_args)
# python Switch_Register_Manager.py -a is performed inside the utils/run.py script, just before the mininet shell starts

stop:
	sudo mn -c

build: dirs $(compiled_json)

%.json: %.p4
	$(P4C) --p4v 16 $(P4C_ARGS) -o $(BUILD_DIR)/$@ $<

dirs:
	mkdir -p $(BUILD_DIR) $(PCAP_DIR) $(LOG_DIR)

clean: stop
	rm -f *.pcap
	rm -rf $(BUILD_DIR) $(PCAP_DIR) $(LOG_DIR)
	rm -f log.log
switch1: 
	sudo simple_switch_grpc build/Raft.json -i 2@ve_B -i 3@enp2s0 -i 4@enp1s0 --thrift-port 9090 -- --grpc-server-addr 0.0.0.0\:50051

switch2: 
	sudo simple_switch_grpc build/Raft.json -i 2@ve_B -i 3@enp2s0 --thrift-port 9091 -- --grpc-server-addr 0.0.0.0\:50052

switch3: 
	sudo simple_switch_grpc build/Raft.json -i 2@ve_B -i 3@ens3 --thrift-port 9092 -- --grpc-server-addr 0.0.0.0\:50053
