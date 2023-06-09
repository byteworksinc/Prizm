{$optimize 7}
{---------------------------------------------------------------}
{								}
{  Prism - Common module for the expandable desktop system	}
{								}
{  By Mike Westerfield						}
{								}
{  Copyright 1988, 1991						}
{  Byte Works, Inc.						}
{								}
{---------------------------------------------------------------}

program Prism(output);

{$segment 'Prism'}

uses Common, QuickDrawII, EventMgr, WindowMgr, ControlMgr, MenuMgr,
     DeskMgr, ToolLocator, ListMgr, MemoryMgr, MscToolSet, GSOS, ORCAShell;

{$LibPrefix '0/obj/'}

uses PCommon, Orca, Buffer, Find, Print, Run;

{-- Global variables ----------------------------------------------------------}

var
					{msc}
					{---}
   done: boolean;			{are we done yet?}

					{events}
					{------}
   device: longint;                     {disk insert device}
   event: integer;			{event #; returned by TaskMaster}
   lastEvent: eventRecord;		{last event returned in event loop}

{------------------------------------------------------------------------------}

procedure InstallIntercepts; extern;

{ install shell intercepts					}


procedure RemoveIntercepts; extern;

{ remove shell intercepts					}

{-- Initialization and termination --------------------------------------------}

procedure FindPrefix8;

{ Make sure prefix 8 is avaliable				}

const
   alertID = 3001;			{alert strng resource ID}

var
   button: integer;			{button pushed}
   done: boolean;			{for loop termination}
   giDCB: getFileInfoOSDCB;		{for checking the prefix}
   prDCB: getPrefixOSDCB;		{get/set prefix DCB}
   prefix8: gsosOutString;		{prefix name}
   pPtr: pStringPtr;			{prompt name pointer}

begin {FindPrefix8}
prDCB.pcount := 2;
prDCB.prefixNum := 8;
prefix8.maxSize := osMaxSize;
prDCB.prefix := @prefix8;
GetPrefixGS(prDCB);
giDCB.pcount := 4;
giDCB.pathName := @prefix8.theString;
pPtr := OSStringToPString(@prefix8.theString);
repeat
   GetFileInfoGS(giDCB);
   done := ToolError = 0;
   if not done then begin
      ResetCursor;
      button := AlertWindow($0005, @pPtr, base + alertID);
      done := button = 0;
      end; {if}
until done;
end; {FindPrefix8}


procedure InstallLanguages;

{ build the languages menu					}

label 1;

var
   gcDCB: GetCommandDCB; 		{Get Command parameter block}
   item: integer;			{menu item #}
   lrec: languageRecPtr; 		{work pointer}

begin {InstallLanguages}
item := 571;				{set the first item number}
with gcDCB do begin			{scan the command table...}
   index := 1;
   repeat
      GetCommand(gcDCB); 		{get a command}
      if (command < 0) and (length(name) <> 0) then begin
	 new(lrec);			{if it is a language then...}
	 if lrec = nil then begin
	    OutOfMemory;
	    goto 1;
	    end; {if}
	 with lrec^ do begin		{fill in the language record values}
	    number := command & $7FFF;
	    name := gcDCB.name;
	    restart := gcDCB.restart <> 0;
	    menuName := concat('--',name,'\N',cnvis(item),chr(13));
	    InsertMItem(@menuName,-1,9);
	    menuItem := item;
	    next := languages;
	    end; {with}
	 languages := lrec;		{put it in the linked list}
	 item := item+1; 		{update item number for next entry}
	 end; {if}
      index := index+1;			{next command...}
   until length(name) = 0;
   end; {with}
1:
CalcMenuSize(0,0,9);			{resize the menu}
end; {InstallLanguages}


procedure InitMenus;

{ Initialize the menu bar.					}

const
   menuID = 1;				{menu bar resource ID}

var
   height: integer;			{height of the largest menu}
   menuBarHand: menuBarHandle;		{for 'handling' the menu bar}

begin {InitMenus}
					{create the menu bar}
menuBarHand := NewMenuBar2(refIsResource, base + menuID, nil);
SetSysBar(menuBarHand);
SetMenuBar(nil);
FixAppleMenu(1);			{add desk accessories}
height := FixMenuBar;			{draw the completed menu bar}
DrawMenuBar;
end; {InitMenus}


procedure InitScalars;

{ Set up the global variables					}

begin {InitScalars}
windowMenuList := nil;			{no windows in the list}
end; {InitScalars}


procedure GetScreenPointer;

{ Get a pointer to screen memory				}

begin {GetScreenPointer}
screenPtr := GetPort^.portInfo.ptrToPixelImage;
end; {GetScreenPointer}

{-- Main program --------------------------------------------------------------}

begin {Prism}
InitScalars;				{set up our variables}
startStopParm :=                        {start up the tools}
   StartUpTools(userID, 2, base+1);
if ToolError <> 0 then
   SysFailMgr(ToolError, @'Could not start tools: ');
GetScreenPointer;			{get pointer to screen memory}
InstallIntercepts;			{install shell intercepts}
SetPenMode(0);				{set pen mode to copy}
InitMenus;				{set up the menu bar}
SetMenuState(nullMenu);			{undefined menu state}
InstallLanguages;			{read the languages file}
InitRun; 				{set up the Run module}
InitPrinter;				{set up the Print module}
InitORCA;				{set up the ORCA module}
InitCursor;				{show the cursor}
ShowCursor;
FindPrefix8;				{make sure prefix 8 is available}
CheckMenuItems;				{check the proper menu items}

done := false;				{main event loop}
repeat
   device := HandleDiskInsert($C000, 0);
   lastEvent.taskMask := $001E3DFF;
   if frWPtr <> nil then
      if frWPtr = FrontWindow then
         lastEvent.taskMask := $001F3DFF;
   event := TaskMaster($076E,lastEvent);
   Events(lastEvent,event,done,false);
until done;

RemoveIntercepts;			{remove shell intercepts}
ShutDownTools(1, startStopParm);        {shut down the tools}
end. {Prism}

{$append 'prism.asm'}
