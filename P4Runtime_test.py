# ALREADY DONE IN s1-runtime.json
# INTENDED AS AN EXAMPLE FOR FUTURE DEVELOPMENT

#!/usr/bin/env python2
import grpc
import os, sys
from time import sleep

# Import P4Runtime lib from parent utils dir
# Probably there's a better way of doing this.
sys.path.append(
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 'utils/p4runtime_lib'))
import bmv2
from error_utils import printGrpcError
from switch import ShutdownAllSwitchConnections
import helper

p4info_file_path = "build/Raft.p4.p4info.txt"
p4info_helper = helper.P4InfoHelper(p4info_file_path)

s1 = bmv2.Bmv2SwitchConnection(
    name='s1',
    address='127.0.0.1:50051',
    device_id=0,
    proto_dump_file='logs/s1-p4runtime-requests_my_py.txt')

s1.MasterArbitrationUpdate()

table_entry2 = p4info_helper.buildTableEntry(
  table_name="MyIngress.follower",
  match_fields={
    "meta.raft_metadata.role": 0,
    "hdr.raft.messageType": 10,
    "hdr.ipv4.dstAddr": [0x0, 0xa, 1]
  },
  action_name="MyIngress.follower_timeout",
  action_params={}
  )

s1.WriteTableEntry(table_entry2)
print("Installed leader table entry rule on {}".format(s1.name))

def install_s1__entry_rule(): # DO NOT USE
    # ALREADY DONE IN s1-runtime.json
    # INTENDED AS AN EXAMPLE FOR FUTURE DEVELOPMENT

    #!/usr/bin/env python2
    import grpc
    import os
    from time import sleep

    # Import P4Runtime lib from parent utils dir
    # Probably there's a better way of doing this.
    sys.path.append(
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     'utils/p4runtime_lib'))
    import bmv2
    from error_utils import printGrpcError
    from switch import ShutdownAllSwitchConnections
    import helper

    p4info_file_path = "build/Raft.p4.p4info.txt"
    p4info_helper = helper.P4InfoHelper(p4info_file_path)

    s1 = bmv2.Bmv2SwitchConnection(
        name='s1',
        address='127.0.0.1:50051',
        device_id=0,
        proto_dump_file='logs/s1-p4runtime-requests_my_py.txt')

    s1.MasterArbitrationUpdate()

    table_entry = p4info_helper.buildTableEntry(
        table_name="MyIngress.leader",
        match_fields={
            "meta.raft_metadata.role": 2,
            "hdr.raft.messageType": 2
        },
        action_name="MyIngress.spread_new_request",
        action_params={}
        )

    table_entry2 = p4info_helper.buildTableEntry(
      table_name="MyIngress.follower",
      match_fields={
        "meta.raft_metadata.role": 0,
        "hdr.raft.messageType": 10,
        "hdr.ipv4.dstAddr": ["10.0.1.254", 32]
      },
      action_name="MyIngress.follower_timeout",
      action_params={}
    )

    s1.WriteTableEntry(table_entry)
    s1.WriteTableEntry(table_entry2)
    print("Installed leader table entry rule on {}".format(s1.name))