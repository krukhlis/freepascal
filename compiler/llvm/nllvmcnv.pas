{
    Copyright (c) 2014 by Jonas Maebe

    Generate LLVM IR for type converting nodes

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}
unit nllvmcnv;

{$i fpcdefs.inc}

interface

    uses
      symtype,
      node,ncnv,ncgcnv,defcmp;

    type
       tllvmtypeconvnode = class(tcgtypeconvnode)
         public
          class function target_specific_need_equal_typeconv(fromdef, todef: tdef): boolean; override;
         protected
          function first_int_to_real: tnode; override;
          function first_int_to_bool: tnode; override;
          function first_nil_to_methodprocvar: tnode; override;
          procedure second_int_to_int;override;
         { procedure second_string_to_string;override; }
         { procedure second_cstring_to_pchar;override; }
         { procedure second_string_to_chararray;override; }
         { procedure second_array_to_pointer;override; }
         procedure second_pointer_to_array;override;
         { procedure second_chararray_to_string;override; }
         { procedure second_char_to_string;override; }
         procedure second_int_to_real;override;
         { procedure second_real_to_real;override; }
         { procedure second_cord_to_pointer;override; }
         procedure second_proc_to_procvar;override;
         procedure second_nil_to_methodprocvar; override;
         { procedure second_bool_to_int;override; }
         procedure second_int_to_bool;override;
         { procedure second_load_smallset;override;  }
         { procedure second_ansistring_to_pchar;override; }
         { procedure second_pchar_to_string;override; }
         { procedure second_class_to_intf;override; }
         { procedure second_char_to_char;override; }
          procedure second_nothing; override;
       end;

implementation

uses
  globtype,globals,verbose,
  aasmbase,aasmdata,
  llvmbase,aasmllvm,
  procinfo,
  symconst,symdef,defutil,
  cgbase,cgutils,tgobj,hlcgobj,pass_2;

{ tllvmtypeconvnode }


class function tllvmtypeconvnode.target_specific_need_equal_typeconv(fromdef, todef: tdef): boolean;
  begin
    result:=
      (fromdef<>todef) and
      { two procdefs that are structurally the same but semantically different
        still need a convertion }
      (
       ((fromdef.typ=procvardef) and
        (todef.typ=procvardef))
      );
  end;


function tllvmtypeconvnode.first_int_to_real: tnode;
  begin
    expectloc:=LOC_FPUREGISTER;
    result:=nil;
  end;


function tllvmtypeconvnode.first_int_to_bool: tnode;
  begin
    result:=inherited;
    if not assigned(result) then
      begin
        if not((nf_explicit in flags) and
               not(left.location.loc in [LOC_FLAGS,LOC_JUMP])) then
          expectloc:=LOC_JUMP;
      end;
  end;


function tllvmtypeconvnode.first_nil_to_methodprocvar: tnode;
  begin
    result:=inherited;
    if assigned(result) then
      exit;
    expectloc:=LOC_REFERENCE;
  end;


procedure tllvmtypeconvnode.second_int_to_int;
  var
    fromsize, tosize: tcgint;
    hreg: tregister;
  begin
    if not(nf_explicit in flags) then
      hlcg.g_rangecheck(current_asmdata.CurrAsmList,left.location,left.resultdef,resultdef);
    fromsize:=left.resultdef.size;
    tosize:=resultdef.size;
    location_copy(location,left.location);
    if not(left.location.loc in [LOC_REFERENCE,LOC_CREFERENCE]) or
       ((fromsize<>tosize) and
        not is_void(left.resultdef)) then
      begin
        hlcg.location_force_reg(current_asmdata.CurrAsmList,location,left.resultdef,resultdef,left.location.loc=LOC_CREGISTER);
      end
    else if left.resultdef<>resultdef then
      begin
        { just typecast the pointer type }
        hreg:=hlcg.getaddressregister(current_asmdata.CurrAsmList,cpointerdef.getreusable(resultdef));
        hlcg.a_loadaddr_ref_reg(current_asmdata.CurrAsmList,left.resultdef,cpointerdef.getreusable(resultdef),left.location.reference,hreg);
        hlcg.reference_reset_base(location.reference,cpointerdef.getreusable(resultdef),hreg,0,location.reference.alignment);
      end;
  end;


procedure tllvmtypeconvnode.second_pointer_to_array;
  var
    hreg: tregister;
  begin
    inherited;
    { insert type conversion }
    hreg:=hlcg.getaddressregister(current_asmdata.CurrAsmList,cpointerdef.getreusable(resultdef));
    hlcg.a_loadaddr_ref_reg(current_asmdata.CurrAsmList,tpointerdef(left.resultdef).pointeddef,cpointerdef.getreusable(resultdef),location.reference,hreg);
    reference_reset_base(location.reference,hreg,0,location.reference.alignment);
  end;


procedure tllvmtypeconvnode.second_int_to_real;
  var
    op: tllvmop;
    llvmtodef: tdef;
  begin
    if is_signed(left.resultdef) then
      op:=la_sitofp
    else
      op:=la_uitofp;
    { see comment about currency in thlcgllvm.a_loadfpu_ref_reg }
    if not(tfloatdef(resultdef).floattype in [s64comp,s64currency]) then
      llvmtodef:=resultdef
    else
      llvmtodef:=s80floattype;
    location_reset(location,LOC_FPUREGISTER,def_cgsize(llvmtodef));
    location.register:=hlcg.getfpuregister(current_asmdata.CurrAsmList,llvmtodef);
    hlcg.location_force_reg(current_asmdata.CurrAsmList,left.location,left.resultdef,left.resultdef,true);
    current_asmdata.CurrAsmList.concat(taillvm.op_reg_size_reg_size(op,location.register,left.resultdef,left.location.register,llvmtodef));
  end;


procedure tllvmtypeconvnode.second_proc_to_procvar;
  begin
    inherited;
    if not tabstractprocdef(resultdef).is_addressonly and
       not tabstractprocdef(left.resultdef).is_addressonly then
      begin
        if location.loc<>LOC_REFERENCE then
          internalerror(2015111902);
        hlcg.g_ptrtypecast_ref(current_asmdata.CurrAsmList,
          cpointerdef.getreusable(tprocdef(left.resultdef).getcopyas(procvardef,pc_normal)),
          cpointerdef.getreusable(resultdef),
          location.reference);
      end;
  end;


procedure tllvmtypeconvnode.second_nil_to_methodprocvar;
  var
    href: treference;
  begin
    tg.gethltemp(current_asmdata.CurrAsmList,resultdef,resultdef.size,tt_normal,href);
    location_reset_ref(location,LOC_REFERENCE,def_cgsize(resultdef),href.alignment);
    location.reference:=href;
    hlcg.g_ptrtypecast_ref(current_asmdata.CurrAsmList,cpointerdef.getreusable(resultdef),cpointerdef.getreusable(methodpointertype),href);
    hlcg.g_load_const_field_by_name(current_asmdata.CurrAsmList,trecorddef(methodpointertype),0,'proc',href);
    hlcg.g_load_const_field_by_name(current_asmdata.CurrAsmList,trecorddef(methodpointertype),0,'self',href);
  end;


procedure tllvmtypeconvnode.second_int_to_bool;
  var
    truelabel,
    falselabel: tasmlabel;
    newsize  : tcgsize;
  begin
    secondpass(left);
    if codegenerror then
      exit;

    { Explicit typecasts from any ordinal type to a boolean type }
    { must not change the ordinal value                          }
    if (nf_explicit in flags) and
       not(left.location.loc in [LOC_FLAGS,LOC_JUMP]) then
      begin
         location_copy(location,left.location);
         newsize:=def_cgsize(resultdef);
         { change of size? change sign only if location is LOC_(C)REGISTER? Then we have to sign/zero-extend }
         if (tcgsize2size[newsize]<>tcgsize2size[left.location.size]) or
            ((newsize<>left.location.size) and (location.loc in [LOC_REGISTER,LOC_CREGISTER])) then
           hlcg.location_force_reg(current_asmdata.CurrAsmList,location,left.resultdef,resultdef,true)
         else
           location.size:=newsize;
         exit;
      end;

    case left.location.loc of
      LOC_SUBSETREG,LOC_CSUBSETREG,LOC_SUBSETREF,LOC_CSUBSETREF,
      LOC_CREFERENCE,LOC_REFERENCE,LOC_REGISTER,LOC_CREGISTER:
        begin
          current_asmdata.getjumplabel(truelabel);
          current_asmdata.getjumplabel(falselabel);
          location_reset_jump(location,truelabel,falselabel);

          hlcg.a_cmp_const_loc_label(current_asmdata.CurrAsmList,left.resultdef,OC_EQ,0,left.location,location.falselabel);
          hlcg.a_jmp_always(current_asmdata.CurrAsmList,location.truelabel);
        end;
      LOC_JUMP :
        begin
          location:=left.location;
        end;
      else
        internalerror(10062);
    end;
  end;


procedure tllvmtypeconvnode.second_nothing;
  var
    hreg: tregister;
  begin
    if left.resultdef<>resultdef then
      begin
        { handle sometype(voidptr^) and "absolute" }
        if not is_void(left.resultdef) and
           not(nf_absolute in flags) and
           (left.resultdef.typ<>formaldef) and
          (left.resultdef.size<>resultdef.size) then
          internalerror(2014012216);
        hlcg.location_force_mem(current_asmdata.CurrAsmList,left.location,left.resultdef);
        hreg:=hlcg.getaddressregister(current_asmdata.CurrAsmList,cpointerdef.getreusable(resultdef));
        hlcg.a_loadaddr_ref_reg(current_asmdata.CurrAsmList,left.resultdef,cpointerdef.getreusable(resultdef),left.location.reference,hreg);
        location_reset_ref(location,left.location.loc,left.location.size,left.location.reference.alignment);
        reference_reset_base(location.reference,hreg,0,location.reference.alignment);
      end
    else
      location_copy(location,left.location);
  end;

begin
  ctypeconvnode:=tllvmtypeconvnode;
end.
