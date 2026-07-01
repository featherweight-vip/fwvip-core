.. Featherweight VIP Common documentation master file, created by
   sphinx-quickstart on Sat Nov 15 15:12:45 2025.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Featherweight VIP Common documentation
======================================

Featherweight VIP builds lightweight, synthesizable Verification IP for digital protocols in
two layers: a methodology-independent, formally-verified **transactor kit**
(``fw-proto-<proto>``) wrapped by thin **methodology layers** (UVM, cocotb) in a
per-protocol **VIP** (``fwvip-<proto>``). Because the protocol/timing reasoning is solved
once in the verified core, the transactors and tests built on top are correct and **fast by
construction**.

This package, ``fwvip-core``, is the shared infrastructure both layers rely on:
clock/reset transactors and their UVM config providers, ready/valid FIFO primitives, and the
cocotb performance pattern. The protocol transactors themselves live in the kits; the VIP
methodology layers are built with the ``create_vip`` skill.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   overview
   transactors
   uvm
   cocotb-performance
   checklist

