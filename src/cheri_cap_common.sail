/*========================================================================*/
/*                                                                        */
/*  Copyright (c) 2015-2019 Robert M. Norton                              */
/*  Copyright (c) 2015-2019 Kathyrn Gray                                  */
/*  All rights reserved.                                                  */
/*                                                                        */
/*  This software was developed by the University of Cambridge Computer   */
/*  Laboratory as part of the Rigorous Engineering of Mainstream Systems  */
/*  (REMS) project, funded by EPSRC grant EP/K008528/1.                   */
/*                                                                        */
/*  Redistribution and use in source and binary forms, with or without    */
/*  modification, are permitted provided that the following conditions    */
/*  are met:                                                              */
/*  1. Redistributions of source code must retain the above copyright     */
/*     notice, this list of conditions and the following disclaimer.      */
/*  2. Redistributions in binary form must reproduce the above copyright  */
/*     notice, this list of conditions and the following disclaimer in    */
/*     the documentation and/or other materials provided with the         */
/*     distribution.                                                      */
/*                                                                        */
/*  THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS''    */
/*  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED     */
/*  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A       */
/*  PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR   */
/*  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,          */
/*  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT      */
/*  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF      */
/*  USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND   */
/*  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,    */
/*  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT    */
/*  OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF    */
/*  SUCH DAMAGE.                                                          */
/*========================================================================*/


let max_otype = MAX(otype_width)
type CapAddr = bits(cap_addr_width)

/* When saving/restoring capabilities xor them with bits of null_cap --
 * this ensures that canonical null_cap is always all-zeros in memory
 * even though it may have bits set logically (e.g. length or exponent
 */

let null_cap_bits : CapBits = capToBits(null_cap)

function capToMemBits(cap) : Capability -> CapBits =
  capToBits(cap) ^ null_cap_bits

function memBitsToCapability(tag, b) : (bool, CapBits) -> Capability =
  capBitsToCapability(tag, b ^ null_cap_bits)

function getCapPerms(cap) : Capability -> bits(31) =
    let perms : bits(15) = EXTZ(getCapHardPerms(cap)) in
    EXTZ(cap.uperms @ perms)

function setCapPerms(cap, perms) : (Capability, bits(31)) -> Capability =
    { cap with
      uperms                 = truncate(perms[30..15], uperms_width),
      /* 14..12 reserved -- ignore */
      permit_set_CID         = perms[11],
      access_system_regs     = perms[10],
      permit_unseal          = perms[9],
      permit_ccall           = perms[8],
      permit_seal            = perms[7],
      permit_store_local_cap = perms[6],
      permit_store_cap       = perms[5],
      permit_load_cap        = perms[4],
      permit_store           = perms[3],
      permit_load            = perms[2],
      permit_execute         = perms[1],
      global                 = perms[0]
      }

/*!
Gets the architecture specific capability flags for given capability.
 */
val getCapFlags : Capability -> CFlags
function getCapFlags(cap) = cap.flag_cap_mode /* NB cast from bool to bits(1) */

/*!
THIS`(cap, flags)` sets the architecture specific capability flags on `cap` to `flags` and returns the result as new capability.
 */
val setCapFlags : (Capability, CFlags) -> Capability
function setCapFlags(cap, flags) = {cap with flag_cap_mode = flags[0]}

function sealCap(cap, otyp) : (Capability, bits(24)) -> (bool, Capability) =
    (true, {cap with sealed=true, otype=truncate(otyp, otype_width)})

function unsealCap(cap) : Capability -> Capability =
    {cap with sealed=false, otype=ones()}


function getCapBase(c) : Capability -> CapAddrInt =
    let (base, _) = getCapBounds(c) in
    base

function getCapBaseBits(c) : Capability -> CapAddr =
    to_bits(cap_addr_width, getCapBase(c))

function getCapTop (c) : Capability -> CapLen =
    let (_, top) = getCapBounds(c) in
    top

function getCapOffsetBits(c) : Capability -> CapAddr =
    let base : CapAddr = getCapBaseBits(c) in
    c.address - base

function getCapOffset(c) : Capability -> CapAddrInt =
    unsigned(getCapOffsetBits(c))

function getCapLength(c) : Capability -> CapLen =
    let ('base, 'top) = getCapBounds(c) in {
        /* For valid capabilties we expect top >= base and hence
         * length >= 0 but representation does allow top < base in some
         * cases so might encounter on untagged capabilities. Here we just
         * pretend it is a 65-bit quantitiy and wrap.
         */
        assert (not(c.tag) | top >= base);
        (top - base) % pow2(cap_addr_width + 1)
    }

val inCapBounds  : (Capability, CapAddr, CapLen) -> bool
function inCapBounds (cap, addr, size) = {
  let (base, top) = getCapBounds(cap);
  let a = unsigned(addr);
  (a >= base) & ((a + size) <= top)
}

function getCapCursor(cap) : Capability -> CapAddrInt = unsigned(cap.address)

function int_to_cap (offset) : CapAddr -> Capability =
    {null_cap with address = offset}

function capBoundsEqual (c1, c2) : (Capability, Capability) -> bool =
    let (base1, top1) = getCapBounds(c1) in
    let (base2, top2) = getCapBounds(c2) in
    (base1 == base2) & (top1 == top2)

val setCapAddr : (Capability, CapAddr) -> (bool, Capability)
function setCapAddr(c, addr) =
    let newCap = { c with address = addr } in
    let representable = capBoundsEqual(c, newCap) in
    (representable, newCap)

function setCapAddrOrNull (cap, addr) : (Capability, CapAddr) -> Capability =
  let (representable, newCap) = setCapAddr(cap, addr) in
  if representable then newCap else int_to_cap(addr)

function setCapOffset(c, offset) : (Capability, CapAddr) -> (bool, Capability) =
    let base = getCapBaseBits(c) in
    let newAddress = base + offset in
    let newCap     = { c with address = newAddress } in
    let representable = capBoundsEqual(c, newCap) in
/*  let representable = fastRepCheck(c, (newAddress - c.address)) in */
    (representable, newCap)

function setCapOffsetOrNull (cap, offset) : (Capability, CapAddr) -> Capability =
    let (representable, newCap) = setCapOffset(cap, offset) in
    if representable & not(cap.sealed) then newCap else int_to_cap(newCap.address)

function incCapOffset(c, delta) : (Capability, CapAddr) -> (bool, Capability) =
    let newAddress : CapAddr = c.address + delta in
    let newCap     = { c with address = newAddress } in
    let representable = capBoundsEqual(c, newCap) in
/*  let representable = fastRepCheck(c, delta) in */
    (representable, newCap)


val capToString : (Capability) -> string effect {escape}
function capToString (cap) = {
  let len = getCapLength(cap);
  let len_str = BitStr(to_bits(68, len));
  /* Print architectural type which is -1 for unsealed caps */
  let otype64 : CapAddr = if cap.sealed then EXTZ(cap.otype) else ones();
  concat_str(" t:",
  concat_str(if cap.tag then "1" else "0",
  concat_str(" s:",
  concat_str(if cap.sealed then "1" else "0",
  concat_str(" perms:",
  concat_str(BitStr(0b0 @ getCapPerms(cap)),
  concat_str(" type:",
  concat_str(BitStr(otype64),
  concat_str(" offset:",
  concat_str(BitStr(getCapOffsetBits(cap)),
  concat_str(" base:",
  concat_str(BitStr(getCapBaseBits(cap)),
  concat_str(" length:", len_str)))))))))))))
}
