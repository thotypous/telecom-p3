import GetPut::*;
import FIFOF::*;
import LFSR::*;
import Clocks::*;
import Vector::*;

typedef struct {
    Vector#(6, Bit#(8)) mac;
    Vector#(4, Bit#(8)) ip;
} ArpReplyTarget deriving (Bits, Eq);

interface EthernetTx;
    interface Put#(ArpReplyTarget) request;
    method Bit#(1) eth_tx_p;
    method Bit#(1) eth_tx_n;
endinterface

module mkEthernetTx#(SyncBitIfc#(Bit#(1)) rxActivity)(EthernetTx);
    Integer nlpPeriodCycles = 324_000;
    Integer nlpWidthCycles = 2;
    Integer txFrameBits = 576;
    Integer txIpgCycles = 96 * 2;
    Integer txJamCycles = 32 * 2;
    Integer txSlotCyclesLog2 = 10;
    UInt#(4) txMaxBackoffAttempts = 4;

    function Bit#(8) currentTxByte(UInt#(7) byteIndex, ArpReplyTarget peer);
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

    function Bit#(1) currentTxBit(UInt#(10) bitIndex, ArpReplyTarget peer, Bit#(32) fcs);
        UInt#(7) byteIndex = truncate(bitIndex >> 3);
        UInt#(3) bitInByte = truncate(bitIndex);
        if (byteIndex >= 68) begin
            UInt#(5) fcsBitIndex = truncate(bitIndex - 544);
            return fcs[fcsBitIndex];
        end else begin
            return currentTxByte(byteIndex, peer)[bitInByte];
        end
    endfunction

    function Bit#(32) crc32Next(Bit#(32) crc, Bit#(1) data);
        Bit#(1) feedback = crc[0] ^ data;
        Bit#(32) shifted = {1'b0, crc[31:1]};
        return (feedback == 1) ? (shifted ^ 32'hEDB88320) : shifted;
    endfunction

    function Bit#(10) backoffMask(UInt#(4) attempts);
        case (attempts)
            0: return 10'b0000000000;
            1: return 10'b0000000001;
            2: return 10'b0000000011;
            3: return 10'b0000000111;
            4: return 10'b0000001111;
            5: return 10'b0000011111;
            6: return 10'b0000111111;
            7: return 10'b0001111111;
            8: return 10'b0011111111;
            9: return 10'b0111111111;
            default: return 10'b1111111111;
        endcase
    endfunction

    FIFOF#(ArpReplyTarget) requests <- mkFIFOF;
    Reg#(Bit#(1)) ethTxP <- mkReg(0);
    Reg#(Bit#(1)) ethTxN <- mkReg(0);
    Reg#(UInt#(19)) nlpIdleCycles <- mkReg(0);
    Reg#(UInt#(2)) nlpPulseCyclesLeft <- mkReg(0);
    Reg#(Bool) txActive <- mkReg(False);
    Reg#(Bool) txSecondHalf <- mkReg(False);
    Reg#(UInt#(10)) txBitIndex <- mkReg(0);
    Reg#(UInt#(8)) txIpgCyclesLeft <- mkReg(0);
    Reg#(UInt#(8)) channelIdleCycles <- mkReg(0);
    Reg#(UInt#(7)) jamCyclesLeft <- mkReg(0);
    Reg#(UInt#(20)) backoffCyclesLeft <- mkReg(0);
    Reg#(UInt#(4)) collisionAttempts <- mkReg(0);
    LFSR#(Bit#(16)) backoffLfsr <- mkLFSR_16;
    Reg#(Bit#(1)) txBitValue <- mkReg(0);
    Reg#(Bit#(32)) txCrc <- mkReg(32'hFFFFFFFF);
    Reg#(Bit#(32)) txFcs <- mkReg(0);
    Reg#(ArpReplyTarget) txPeer <- mkRegU;

    Bool channelBusy = rxActivity.read == 1;
    Bool localTxActive =
        txActive
        || jamCyclesLeft != 0
        || nlpPulseCyclesLeft != 0;

    rule generate_tx;
        backoffLfsr.next;

        if (channelBusy || localTxActive) begin
            channelIdleCycles <= 0;
        end else if (channelIdleCycles != fromInteger(txIpgCycles)) begin
            // Increment with saturation
            channelIdleCycles <= channelIdleCycles + 1;
        end

        if (txActive) begin
            nlpIdleCycles <= 0;

            // TODO: drive ethTxP/ethTxN with Manchester encoding for txBitValue.

            if (channelBusy) begin
                txActive <= False;
                txSecondHalf <= False;
                txBitIndex <= 0;
                UInt#(4) nextAttempts = (collisionAttempts == txMaxBackoffAttempts) ? txMaxBackoffAttempts : collisionAttempts + 1;
                Bit#(10) backoffSlots = truncate(backoffLfsr.value) & backoffMask(nextAttempts);
                backoffCyclesLeft <= zeroExtend(unpack(backoffSlots)) << txSlotCyclesLog2;
                collisionAttempts <= nextAttempts;
                jamCyclesLeft <= fromInteger(txJamCycles - 1);
            end else begin
                if (txSecondHalf) begin
                    if (txBitIndex >= 64 && txBitIndex < 544) begin
                        let nextCrc = crc32Next(txCrc, txBitValue);
                        txCrc <= nextCrc;
                        if (txBitIndex == 543) begin
                            Bit#(32) nextFcs = ~nextCrc;
                            txFcs <= nextFcs;
                            txBitValue <= nextFcs[0];
                        end
                    end

                    txSecondHalf <= False;
                    if (txBitIndex == fromInteger(txFrameBits - 1)) begin
                        txActive <= False;
                        requests.deq;
                        collisionAttempts <= 0;
                        txBitIndex <= 0;
                        txIpgCyclesLeft <= fromInteger(txIpgCycles);
                    end else begin
                        let nextBitIndex = txBitIndex + 1;
                        txBitIndex <= nextBitIndex;
                        if (txBitIndex != 543) begin
                            txBitValue <= currentTxBit(nextBitIndex, txPeer, txFcs);
                        end
                    end
                end else begin
                    txSecondHalf <= True;
                end
            end
        end else if (jamCyclesLeft != 0) begin
            Bit#(7) jamCount = pack(jamCyclesLeft);
            Bit#(1) jamValue = jamCount[0];
            ethTxP <= jamValue;
            ethTxN <= ~jamValue;
            jamCyclesLeft <= jamCyclesLeft - 1;
            nlpIdleCycles <= 0;
        // TODO: wait for the randomized backoff interval before retrying.
        end else if (txIpgCyclesLeft != 0) begin
            ethTxP <= 0;
            ethTxN <= 0;
            nlpIdleCycles <= 0;
            if (channelBusy) begin
                txIpgCyclesLeft <= fromInteger(txIpgCycles);
            end else begin
                txIpgCyclesLeft <= txIpgCyclesLeft - 1;
            end
        end else if (nlpPulseCyclesLeft != 0) begin
            ethTxP <= 1;
            ethTxN <= 0;
            nlpPulseCyclesLeft <= nlpPulseCyclesLeft - 1;
        // TODO: also defer transmission until the channel has been idle for txIpgCycles.
        end else if (channelBusy) begin
            ethTxP <= 0;
            ethTxN <= 0;
            nlpIdleCycles <= 0;
        end else if (requests.notEmpty) begin
            let peer = requests.first;
            ethTxP <= 0;
            ethTxN <= 0;
            txPeer <= peer;
            txActive <= True;
            txSecondHalf <= False;
            txBitIndex <= 0;
            txBitValue <= 1;
            txCrc <= 32'hFFFFFFFF;
            txFcs <= 0;
            nlpIdleCycles <= 0;
        end else if (nlpIdleCycles == fromInteger(nlpPeriodCycles - 1)) begin
            ethTxP <= 1;
            ethTxN <= 0;
            nlpIdleCycles <= 0;
            nlpPulseCyclesLeft <= fromInteger(nlpWidthCycles - 1);
        end else begin
            ethTxP <= 0;
            ethTxN <= 0;
            nlpIdleCycles <= nlpIdleCycles + 1;
        end
    endrule

    interface request = toPut(requests);
    method eth_tx_p = ethTxP;
    method eth_tx_n = ethTxN;
endmodule
