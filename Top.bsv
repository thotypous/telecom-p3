import RS232::*;
import GetPut::*;
import FIFOF::*;
import Connectable::*;
import Clocks::*;
import Vector::*;
import FrameDelimiter::*;
import RxActivityDetector::*;
import EthernetTx::*;

interface Top;
    interface RS232 rs232;
    interface Reset rs232_rst;
    (* always_ready, prefix="", result="LED" *)
    method Bit#(6) led;
    (* always_ready, prefix="", result="ETH_TX_P" *)
    method Bit#(1) eth_tx_p;
    (* always_ready, prefix="", result="ETH_TX_N" *)
    method Bit#(1) eth_tx_n;
    interface Put#(Bit#(1)) eth_rx;
    interface Reset tx_rst;
endinterface

(* synthesize *)
module mkTop#(Clock clk_uart, Clock clk_tx)(Top);
    function Bool arpRequestFixedByteMatches(UInt#(11) byteIndex, Bit#(8) value);
        case (byteIndex)
            12: return value == 8'h08;
            13: return value == 8'h06;
            14: return value == 8'h00;
            15: return value == 8'h01;
            16: return value == 8'h08;
            17: return value == 8'h00;
            18: return value == 8'h06;
            19: return value == 8'h04;
            20: return value == 8'h00;
            21: return value == 8'h01;
            38: return value == 8'h0A;
            39: return value == 8'h01;
            40: return value == 8'h02;
            41: return value == 8'h03;
            default: return True;
        endcase
    endfunction

    FrameDelimiter frameDelimiter <- mkFrameDelimiter;
    RxActivityDetector rxActivityDetector <- mkRxActivityDetector;

    Reset rst_uart <- mkAsyncResetFromCR(2, clk_uart);
    UART#(16) uart <- mkUART(8, NONE, STOP_1, 1, clocked_by clk_uart, reset_by rst_uart);
    SyncFIFOIfc#(Bit#(8)) uartSync <- mkSyncFIFOFromCC(2, clk_uart);
    mkConnection(toGet(uartSync), uart.rx);

    Reset rst_tx <- mkAsyncResetFromCR(2, clk_tx);
    FIFOF#(ArpReplyTarget) pendingArpTarget <- mkGFIFOF(True, False);
    SyncFIFOIfc#(ArpReplyTarget) arpReplyRequests <- mkSyncFIFOFromCC(2, clk_tx);
    SyncBitIfc#(Bit#(1)) rxActivityToTx <- mkSyncBitFromCC(clk_tx);
    EthernetTx ethernetTx <- mkEthernetTx(rxActivityToTx, clocked_by clk_tx, reset_by rst_tx);
    mkConnection(toGet(pendingArpTarget), toPut(arpReplyRequests));
    mkConnection(toGet(arpReplyRequests), ethernetTx.request);

    // The UART is slower than 10BASE-T Ethernet (2.4 Mbit/s versus 10 Mbit/s),
    // but this FIFO can buffer a complete Ethernet frame
    FIFOF#(Bit#(8)) uartBuffer <- mkGSizedFIFOF(True, False, 1522);
    mkConnection(toGet(uartBuffer), toPut(uartSync));

    Reg#(Bit#(6)) ledCounter <- mkReg(0);
    Reg#(Bool) rxArpRequestMatches <- mkReg(True);
    Reg#(UInt#(11)) rxByteIndex <- mkReg(0);
    Reg#(Vector#(6, Bit#(8))) peerMac <- mkRegU;
    Reg#(Vector#(4, Bit#(8))) peerIp <- mkRegU;

    Reg#(Bit#(8)) deserByte <- mkRegU;
    Reg#(Bit#(3)) deserCounter <- mkReg(0);
    Reg#(Bit#(3)) ethRxSync <- mkReg(0);

    Reg#(Bool) prevActivity <- mkReg(True);

    rule connect_activity;
        rxActivityToTx.send(pack(rxActivityDetector.active));
    endrule

    rule count_activity;
        prevActivity <= rxActivityDetector.active;
        if (!prevActivity && rxActivityDetector.active) begin
            ledCounter <= ledCounter + 1;
        end
    endrule

    rule discard;
        let b <- uart.tx.get;
    endrule

    rule process_frame_bit;
        let frame_bit <- frameDelimiter.out.get;
        case (frame_bit) matches
            tagged Invalid:
                begin
                    deserCounter <= 0;
                    rxByteIndex <= 0;
                    rxArpRequestMatches <= True;
                    if (rxArpRequestMatches && rxByteIndex >= 42) begin
                        pendingArpTarget.enq(ArpReplyTarget {
                            mac: peerMac,
                            ip: peerIp
                        });
                    end
                end
            tagged Valid .b:
                begin
                    // Deserialize payload bits LSB-first and forward complete bytes to the UART
                    let deserByte_ = {b, deserByte[7:1]};
                    if (deserCounter == 7) begin
                        uartBuffer.enq(deserByte_);
                        rxByteIndex <= rxByteIndex + 1;
                        rxArpRequestMatches <= rxArpRequestMatches && arpRequestFixedByteMatches(rxByteIndex, deserByte_);

                        case (rxByteIndex)
                            22: peerMac[0] <= deserByte_;
                            23: peerMac[1] <= deserByte_;
                            24: peerMac[2] <= deserByte_;
                            25: peerMac[3] <= deserByte_;
                            26: peerMac[4] <= deserByte_;
                            27: peerMac[5] <= deserByte_;
                            28: peerIp[0] <= deserByte_;
                            29: peerIp[1] <= deserByte_;
                            30: peerIp[2] <= deserByte_;
                            31: peerIp[3] <= deserByte_;
                        endcase
                    end
                    deserByte <= deserByte_;
                    deserCounter <= deserCounter + 1;
                end
        endcase
    endrule

    interface Put eth_rx;
        method Action put(Bit#(1) in);
            ethRxSync <= {ethRxSync[1:0], in};
            rxActivityDetector.in.put(ethRxSync[2]);
            frameDelimiter.in.put(ethRxSync[2]);
        endmethod
    endinterface
    interface rs232 = uart.rs232;
    interface rs232_rst = rst_uart;
    method led = ~ledCounter;
    method eth_tx_p = ethernetTx.eth_tx_p;
    method eth_tx_n = ethernetTx.eth_tx_n;
    interface tx_rst = rst_tx;
endmodule
