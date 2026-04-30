import Assert::*;
import Clocks::*;
import EthernetTx::*;
import StmtFSM::*;
import Vector::*;

module mkTestRxActivity#(Bit#(1) initialValue)(SyncBitIfc#(Bit#(1)));
    Reg#(Bit#(1)) rxActivity <- mkReg(initialValue);

    method Action send(Bit#(1) newValue);
        rxActivity <= newValue;
    endmethod

    method Bit#(1) read;
        return rxActivity;
    endmethod
endmodule

function Vector#(6, Bit#(8)) makeMac(Bit#(8) a0, Bit#(8) a1, Bit#(8) a2, Bit#(8) a3, Bit#(8) a4, Bit#(8) a5);
    return cons(a0, cons(a1, cons(a2, cons(a3, cons(a4, cons(a5, nil))))));
endfunction

function Vector#(4, Bit#(8)) makeIp(Bit#(8) a0, Bit#(8) a1, Bit#(8) a2, Bit#(8) a3);
    return cons(a0, cons(a1, cons(a2, cons(a3, nil))));
endfunction

function ArpReplyTarget testTarget(UInt#(2) index);
    case (index)
        0: return ArpReplyTarget { mac: makeMac(8'h02, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01), ip: makeIp(8'h0A, 8'h01, 8'h02, 8'h10) };
        1: return ArpReplyTarget { mac: makeMac(8'h12, 8'h34, 8'h56, 8'h78, 8'h9A, 8'hBC), ip: makeIp(8'h0A, 8'h01, 8'h02, 8'h20) };
        default: return ArpReplyTarget { mac: makeMac(8'hFE, 8'hDC, 8'hBA, 8'h98, 8'h76, 8'h54), ip: makeIp(8'h0A, 8'h01, 8'h02, 8'h30) };
    endcase
endfunction

function Bit#(8) expectedByte(UInt#(7) byteIndex, ArpReplyTarget peer);
    case (byteIndex)
        0: return 8'h55;
        1: return 8'h55;
        2: return 8'h55;
        3: return 8'h55;
        4: return 8'h55;
        5: return 8'h55;
        6: return 8'h55;
        7: return 8'hD5;
        8: return peer.mac[0];
        9: return peer.mac[1];
        10: return peer.mac[2];
        11: return peer.mac[3];
        12: return peer.mac[4];
        13: return peer.mac[5];
        14: return 8'hDE;
        15: return 8'hAD;
        16: return 8'hBE;
        17: return 8'hEF;
        18: return 8'hCA;
        19: return 8'hFE;
        20: return 8'h08;
        21: return 8'h06;
        22: return 8'h00;
        23: return 8'h01;
        24: return 8'h08;
        25: return 8'h00;
        26: return 8'h06;
        27: return 8'h04;
        28: return 8'h00;
        29: return 8'h02;
        30: return 8'hDE;
        31: return 8'hAD;
        32: return 8'hBE;
        33: return 8'hEF;
        34: return 8'hCA;
        35: return 8'hFE;
        36: return 8'h0A;
        37: return 8'h01;
        38: return 8'h02;
        39: return 8'h03;
        40: return peer.mac[0];
        41: return peer.mac[1];
        42: return peer.mac[2];
        43: return peer.mac[3];
        44: return peer.mac[4];
        45: return peer.mac[5];
        46: return peer.ip[0];
        47: return peer.ip[1];
        48: return peer.ip[2];
        49: return peer.ip[3];
        default: return 8'h00;
    endcase
endfunction

function Bit#(32) crc32Next(Bit#(32) crc, Bit#(1) data);
    Bit#(1) feedback = crc[0] ^ data;
    Bit#(32) shifted = {1'b0, crc[31:1]};
    return (feedback == 1) ? (shifted ^ 32'hEDB88320) : shifted;
endfunction

function Bit#(1) frameBitNoFcs(UInt#(10) bitIndex, ArpReplyTarget peer);
    UInt#(7) byteIndex = truncate(bitIndex >> 3);
    UInt#(3) bitInByte = truncate(bitIndex);
    return expectedByte(byteIndex, peer)[bitInByte];
endfunction

function Bit#(32) expectedFcs(ArpReplyTarget peer);
    Bit#(32) crc = 32'hFFFFFFFF;
    for (Integer i = 64; i < 544; i = i + 1) begin
        crc = crc32Next(crc, frameBitNoFcs(fromInteger(i), peer));
    end
    return ~crc;
endfunction

function Bit#(1) expectedFrameBit(UInt#(10) bitIndex, ArpReplyTarget peer);
    if (bitIndex >= 544) begin
        UInt#(5) fcsBitIndex = truncate(bitIndex - 544);
        return expectedFcs(peer)[fcsBitIndex];
    end else begin
        return frameBitNoFcs(bitIndex, peer);
    end
endfunction

function Bit#(1) expectedTxP(UInt#(10) bitIndex, Bool secondHalf, ArpReplyTarget peer);
    Bit#(1) bitValue = expectedFrameBit(bitIndex, peer);
    return secondHalf ? bitValue : ~bitValue;
endfunction

function Action assertPins(EthernetTx dut, Bit#(1) expectedP, Bit#(1) expectedN, String message);
    action
        dynamicAssert(dut.eth_tx_p == expectedP && dut.eth_tx_n == expectedN, message);
    endaction
endfunction

function Action assertManchesterPins(EthernetTx dut, UInt#(10) bitIndex, Bool secondHalf, ArpReplyTarget peer, String message);
    action
        let expectedP = expectedTxP(bitIndex, secondHalf, peer);
        if (!(dut.eth_tx_p == expectedP && dut.eth_tx_n == ~expectedP)) begin
            $display("Manchester mismatch: bit=", bitIndex, " secondHalf=", secondHalf, " got p=", dut.eth_tx_p, " n=", dut.eth_tx_n, " expected p=", expectedP, " n=", ~expectedP);
        end
        dynamicAssert(dut.eth_tx_p == expectedP && dut.eth_tx_n == ~expectedP, message);
    endaction
endfunction

function Stmt waitForFrameStart(EthernetTx dut, Reg#(UInt#(16)) tries, UInt#(16) limit);
    return seq
        tries <= 0;
        while (!(dut.eth_tx_p == 0 && dut.eth_tx_n == 1) && tries < limit) action
            tries <= tries + 1;
        endaction
        dynamicAssert(tries < limit, "timed out waiting for EthernetTx frame start");
    endseq;
endfunction

function Stmt checkFrameAfterStart(EthernetTx dut, ArpReplyTarget peer, Reg#(UInt#(10)) bitIndex);
    return seq
        action
            let expectedP = expectedTxP(0, True, peer);
            if (!(dut.eth_tx_p == expectedP && dut.eth_tx_n == ~expectedP)) begin
                $display("Manchester mismatch: bit=", 0, " secondHalf=", True, " got p=", dut.eth_tx_p, " n=", dut.eth_tx_n, " expected p=", expectedP, " n=", ~expectedP);
            end
            dynamicAssert(dut.eth_tx_p == expectedP && dut.eth_tx_n == ~expectedP, "wrong Manchester second half");
            bitIndex <= 1;
        endaction
        while (bitIndex != 576) seq
            assertManchesterPins(dut, bitIndex, False, peer, "wrong Manchester first half");
            action
                let expectedP = expectedTxP(bitIndex, True, peer);
                if (!(dut.eth_tx_p == expectedP && dut.eth_tx_n == ~expectedP)) begin
                    $display("Manchester mismatch: bit=", bitIndex, " secondHalf=", True, " got p=", dut.eth_tx_p, " n=", dut.eth_tx_n, " expected p=", expectedP, " n=", ~expectedP);
                end
                dynamicAssert(dut.eth_tx_p == expectedP && dut.eth_tx_n == ~expectedP, "wrong Manchester second half");
                bitIndex <= bitIndex + 1;
            endaction
        endseq
    endseq;
endfunction
