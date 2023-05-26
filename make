unset exit

Newer prism prism.rez
if {Status} != 0
   set exit on
   echo compile prism.rez keep=prism
   compile prism.rez keep=prism
   unset exit
end

if {#} == 0 then

   set list        obj/prism.a prism.pas prism.asm prism.macros
   set list {list} obj/pcommon.int obj/orca.int obj/buffer.int
   Newer {list}
   if {Status} != 0
      set prism prism
   end

   set list        obj/buffer.a buffer.pas
   set list {list} buffer.asm buffer.macros
   set list {list} obj/pcommon.int
   Newer {list}
   if {Status} != 0
      set buffer buffer
   end

   Newer obj/find.a find.pas obj/pcommon.int obj/buffer.int
   if {Status} != 0
      set find find
   end

   Newer obj/print.a print.pas obj/pcommon.int obj/buffer.int
   if {Status} != 0
      set print print
   end

   set list        obj/run.a run.pas run.asm run.macros
   set list {list} obj/pcommon.int obj/buffer.int
   Newer {list}
   if {Status} != 0
      set run run
   end

   set list        obj/orca.a orca.pas orca.asm orca.macros
   set list {list} obj/pcommon.int obj/find.int obj/print.int obj/run.int
   Newer {list}
   if {Status} != 0
      set orca orca
   end

   Newer obj/pcommon.a pcommon.pas pcommon.asm pcommon.macros
   if {Status} != 0
      set pcommon pcommon
   end

   set exit on
   for i in {pcommon} {buffer} {find} {print} {run} {orca} {prism}
      echo compile +t +e {i}.pas keep=obj/{i}
      compile +t +e {i}.pas keep=obj/{i}
   end

else

   set exit on

   for i in {Parameters}
      echo compile +t +e {i}.pas keep=obj/{i}
      compile +t +e {i}.pas keep=obj/{i}
   end
end

echo set AuxType $DB01
set AuxType $DB01

echo link obj/prism obj/find obj/print obj/run obj/buffer obj/orca obj/pcommon keep=prism
link obj/prism obj/find obj/print obj/run obj/buffer obj/orca obj/pcommon keep=prism

* echo purge
* purge >14/temp

echo prism
prism
