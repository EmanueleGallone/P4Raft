using System;
using System.Net.NetworkInformation;
using CommandLine;
using System.Linq;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using System.Diagnostics;

namespace TrafficGeneratorCsharp
{
    class Program
    {
        public class Options
        {
            [Option('c', "count", Required = false, HelpText = "How many packets to send.")]
            public int PacketCount { get; set; } = 0;

            [Option('r', "rate", Required = false, HelpText = "How many packets per second.")]
            public int PacketsPerSecond { get; set; } = 1000;

            [Option('s', "source", Required = false, HelpText = "Source ID")]
            public short SourceId { get; set; } = 1;

            [Option('d', "destination", Required = false, HelpText = "Destination ID")]
            public short DestinationId { get; set; } = 1;
            
            [Option('m', "messageType", Required= false, HelpText="Specify the message Type")]
            public byte MessageType { get; set; } = 255;
        }

        static void Main(string[] args)
        {
            Parser.Default.ParseArguments<Options>(args)
                .WithParsed<Options>(o => {

                
                int port = 0x9998;
                string raft_ip = "224.255.255.255";
                
                UdpClient client = new UdpClient();
                client.Connect(raft_ip, port);
                
                // Preparazione pacchetto
                byte[] source = new byte[] {
                    0x00,                   // 1Byte type_sourceID;
                    0x00,                   // 1Byte length_sourceID;
                }.Concat(BitConverter.GetBytes(o.SourceId)).ToArray(); // 2Bytes sourceID; // ID of the source Node

                byte[] destination = new byte[] {
                    0x00,                   // 1Byte type_destinationID;
                    0x00,                   // 1Byte length_destinationID;
                }.Concat(BitConverter.GetBytes(o.DestinationId)).ToArray(); // 2Bytes destinationID; // ID of the destination Node

                byte[] logindex = {
                    0x00,                   // 1Byte type_logIndex;
                    0x00,                   // 1Byte length_logIndex;
                    0x00, 0x00, 0x00, 0x00  // 4Bytes logIndex;            // index of the last entry on Leader's log
                };

                byte[] currentTerm = {
                    0x00,                   // 1Byte type_currentTerm;
                    0x00,                   // 1Byte length_currentTerm;
                    0x00, 0x00, 0x00, 0x01, // 4Bytes currentTerm;        // or Epoch
                };

                byte[] data = {
                    0x00,                   // 1Byte type_data;
                    0x00,                   // 1Byte length_data;
                    0x00, 0x00, 0x00, 0x00, // actual value to be pushed inside the log 
                    0x00, 0x00, 0x00, 0x00, // actual value to be pushed inside the log 
                };
                
                byte[] messageType = new byte[] {
                    0x00,                   // 1Byte type_messageType;
                    0x00,                   // 1Byte length_messageType;
                    o.MessageType           // 1Byte messageType;                 // represents the command
                };
                
                byte[] version = {
                    0x00                    // 1Byte version;                     // protocol version
                };

                Stopwatch sw = new Stopwatch();
                Stopwatch innerSw = new Stopwatch();
                innerSw.Start();

                sw.Start();
                var waitMs = (int)((1f / o.PacketsPerSecond) * 1000);
                var waitMicro = (int)((1f / o.PacketsPerSecond) * 1000000);
                
                long counter = 0;
                while (o.PacketCount == 0 || counter < o.PacketCount)
                {
                    byte[] buffer = new byte[34];
                    Buffer.BlockCopy(source, 0, buffer, 0, 4);
                    Buffer.BlockCopy(destination, 0, buffer, 4, 4);
                    Buffer.BlockCopy(logindex, 0, buffer, 8, 6);
                    Buffer.BlockCopy(currentTerm, 0, buffer, 14, 6);
                    
                    Buffer.BlockCopy(new byte[] { 0x00, 0x00}, 0, buffer, 20, 2); // Type e Length del data
                    Buffer.BlockCopy(BitConverter.GetBytes(counter), 0, buffer, 22, 8); // Data to push inside log

                    Buffer.BlockCopy(messageType, 0, buffer, 30, 3);
                    Buffer.BlockCopy(version, 0, buffer, 33, 1);

                    client.Send(buffer, buffer.Length);

                    counter++;

                    if (o.PacketsPerSecond <= 1000)
                        Thread.Sleep(waitMs);
                    else
                    {
                        var start = innerSw.ElapsedMicroseconds();
                        double ms = 0;
                        do 
                        {
                            ms = innerSw.ElapsedMicroseconds();
                        }
                        while (waitMicro > (ms - start));
                    }
                }
                sw.Stop();
                innerSw.Stop();
                Console.WriteLine($"Secondi trascorsi: {sw.Elapsed.TotalSeconds}");

            });
        }
    }
}
