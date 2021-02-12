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

import subprocess
import argparse
import sys

RAFT_MAJORITY = 2


class CustomConsole(object):
    def __init__(self, port):
        self.port = port
        self.output = None
        self._python_version = sys.version_info[0]

    def _console(self):
        if self._python_version == 3:
            return subprocess.Popen(['simple_switch_CLI', '--thrift-port', str(self.port)],
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    encoding='utf-8'
                                    )
        elif self._python_version == 2:
            return subprocess.Popen(['simple_switch_CLI', '--thrift-port', str(self.port)],
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE
                                    )

    def communicate(self, command):
        self.output = self._console().communicate(command)[0]
        return self._clean_output()

    def _clean_output(self):
        self.output = self.output.replace('Obtaining JSON from switch...', '')
        self.output = self.output.replace('Control utility for runtime P4 table manipulation', '')
        self.output = self.output.replace('RuntimeCmd:', '')
        self.output = self.output.replace('Done', '')
        return self.output.strip()


def autoset():
    cmd = CustomConsole(9090)

    print("autosetting all switches")
    cmd.communicate('register_write roleRegister 0 0')
    cmd.communicate('register_write logIndexRegister 0 0')
    cmd.communicate('register_write leaderRegister 0 0')
    cmd.communicate('register_write  majorityRegister 0 {}'.format(RAFT_MAJORITY))
    cmd.communicate('register_write  currentTermRegister 0 0')
    cmd.communicate('register_write  IDRegister 0 1')

    cmd = CustomConsole(9091)
    cmd.communicate('register_write roleRegister 0 0')
    cmd.communicate('register_write logIndexRegister 0 0')
    cmd.communicate('register_write leaderRegister 0 0')
    cmd.communicate('register_write  majorityRegister 0 {}'.format(RAFT_MAJORITY))
    cmd.communicate('register_write  currentTermRegister 0 0')
    cmd.communicate('register_write  IDRegister 0 2')

    cmd = CustomConsole(9092)
    cmd.communicate('register_write roleRegister 0 0')
    cmd.communicate('register_write logIndexRegister 0 0')
    cmd.communicate('register_write leaderRegister 0 0')
    cmd.communicate('register_write  majorityRegister 0 {}'.format(RAFT_MAJORITY))
    cmd.communicate('register_write  currentTermRegister 0 0')
    cmd.communicate('register_write  IDRegister 0 3')


def external_autoset():
    autoset()

# example using thrift adding ternary match:
# table_add follower follower_timeout 0 10 167772670&&&167772870 => 1


if __name__ == '__main__':
    # TODO implement a subparser
    parser = argparse.ArgumentParser(description='Switch Register Tool')
    parser.add_argument(
        '-port', '--thrift-port', help='Select Switch (s1 -> 9090, s2 -> 9091, s3 -> 9092)', default=9090
    )
    parser.add_argument(
        '-rw', '--register-write', help='select register to write', type=str, default=None, required=False
    )
    parser.add_argument('-r', '--register-read', help='select register to read', required=False)
    parser.add_argument('-d', '--data', help='Data to write inside the register', type=int, default=None, required=False)
    parser.add_argument(
        '-ra', '--read-all', help='prints all the registers\' content', required=False, action='store_true'
    )
    parser.add_argument('-a', '--autoset', help='debug method to write all the commands needed to set the network',
        required=False,
        action='store_true'
    )
    args = parser.parse_args()

    cmd = CustomConsole(args.thrift_port)

    if args.autoset:
        autoset()
        

    if args.read_all:
        print('Printing all the registers: \n')
        number_of_log_registers = 32
        print(  # list comprehension
            [cmd.communicate('register_read logValueRegister ' + str(i) + '\n')
             for i in range(0, number_of_log_registers)]
        )
        print('')  # no, \n doesn't work
        print(cmd.communicate('register_read logIndexRegister 0 '))
        print('')
        print(cmd.communicate('register_read IDRegister 0 '))
        print('')
        print(cmd.communicate('register_read leaderRegister 0'))
        print('')
        print(cmd.communicate('register_read currentTermRegister 0'))
        print('')
        print(cmd.communicate('register_read countLogACKRegister 0'))
        print('')
        print(cmd.communicate('register_read countVoteRegister 0'))
        print('')
        print(cmd.communicate('register_read roleRegister 0').replace('= 0', '= Follower').replace('= 1', '= Candidate').replace('= 2', '= Leader'))
        print('')
        print(cmd.communicate('register_read majorityRegister 0'))
        print('')
        print(cmd.communicate('register_read stagedValueRegister 0'))

    if args.register_write and args.data:  # writing inside a register
        index = 0  # TODO add inside the subparser!
        command = 'register_write {} {} {}'.format(args.register_write, index, args.data)
        cmd.communicate(command=command)  # No feedback output due to runtime_CLI, not me!
