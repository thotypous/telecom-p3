import Assert::*;
import Clocks::*;
import EthernetTx::*;
import GetPut::*;
import StmtFSM::*;
import CommonEthernetTxTest::*;

(* synthesize *)
module mkTestEthernetTxCollisionBackoff(Empty);
    SyncBitIfc#(Bit#(1)) rxActivityIfc <- mkTestRxActivity(0);
    EthernetTx dut <- mkEthernetTx(rxActivityIfc);
    Reg#(UInt#(16)) tries <- mkReg(0);
    Reg#(UInt#(7)) jamCycle <- mkReg(0);
    Reg#(UInt#(3)) collisionCount <- mkReg(0);
    Reg#(UInt#(16)) idleCycles <- mkReg(0);
    Reg#(Bool) observedNonZeroBackoff <- mkReg(False);
    ArpReplyTarget peer = testTarget(1);

    mkAutoFSM(seq
        dut.request.put(peer);
        waitForFrameStart(dut, tries, 5000);

        // With the default 16-bit LFSR, all-zero backoff for four attempts is
        // unlikely: 1/2 * 1/4 * 1/8 * 1/16 = 1/1024.
        while (collisionCount != 4) seq
            repeat (40) action
                dynamicAssert(dut.eth_tx_p != dut.eth_tx_n, "EthernetTx stopped before injected collision");
            endaction

            rxActivityIfc.send(1);
            delay(1);
            action
                rxActivityIfc.send(0);
                jamCycle <= 0;
            endaction
            while (jamCycle != 63) action
                Bit#(1) expectedP = ~pack(jamCycle)[0];
                if (!(dut.eth_tx_p == expectedP && dut.eth_tx_n == ~expectedP)) begin
                    $display("Jam mismatch: cycle=", jamCycle, " got p=", dut.eth_tx_p, " n=", dut.eth_tx_n, " expected p=", expectedP, " n=", ~expectedP);
                end
                dynamicAssert(dut.eth_tx_p == expectedP && dut.eth_tx_n == ~expectedP, "wrong jam pattern after collision");
                jamCycle <= jamCycle + 1;
            endaction

            idleCycles <= 0;
            while (!(dut.eth_tx_p == 0 && dut.eth_tx_n == 1) && idleCycles < 20000) action
                dynamicAssert(dut.eth_tx_p == 0 && dut.eth_tx_n == 0, "EthernetTx drove unexpected pins while waiting for backoff retry");
                idleCycles <= idleCycles + 1;
            endaction

            action
                dynamicAssert(idleCycles < 20000, "timed out waiting for retry after collision");
                dynamicAssert(idleCycles >= 192, "retry happened before channel idle interval elapsed");
                if (idleCycles > 256) begin
                    observedNonZeroBackoff <= True;
                end

                collisionCount <= collisionCount + 1;
            endaction
        endseq

        dynamicAssert(observedNonZeroBackoff, "did not observe any non-zero backoff interval after collisions");
        repeat (80) action
            dynamicAssert(dut.eth_tx_p != dut.eth_tx_n, "EthernetTx did not restart transmission after backoff");
        endaction
        $display("SUCCESS");
        $finish(0);
    endseq);
endmodule
