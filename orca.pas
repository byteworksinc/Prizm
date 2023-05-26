{$optimize 7}
{---------------------------------------------------------------}
{								}
{  This is the ORCA programming module for the prism integrated }
{  desktop environment.						}
{								}
{  By Mike Westerfield						}
{								}
{  Copyright 1988						}
{  Byte Works, Inc.						}
{								}
{---------------------------------------------------------------}

unit ORCA;

{-- Interface --------------------------------------------------}

interface

{$segment 'Prism'}
  
uses Common, QuickDrawII, EventMgr, WindowMgr, MenuMgr, MemoryMgr, ControlMgr,
     ScrapMgr, MscToolSet, DeskMgr, DialogMgr, SFToolSet, ORCAShell, GSOS;

{$LibPrefix '0/obj/'}

uses PCommon, Buffer, Find, Run, Print;

{---------------------------------------------------------------}

var
   oldSelection: boolean;		{was text selected last time thru loop?}

{---------------------------------------------------------------}

procedure CheckMenuItems;

{ check and uncheck file dependent menu items			}


procedure DoShowRuler;

{ show or hide the ruler 					}
{								}
{ Notes: Declared externally in Buffer.pas			}


procedure EditIntercept;

{ intercept handler for the EDIT command 			}


procedure Events (lastEvent: eventRecord; event: integer;
  var done: boolean; executing: boolean);

{ handle the main event loop					}
{								}
{ Parameters:							}
{    lastEvent - event record					}
{    event - event number					}
{    done -							}
{    executing - is a program executing? 			}


procedure InitORCA;

{ Do one-time initialization for this module			}

{-- Implementation ---------------------------------------------}

implementation

var
   cancelButton: boolean;		{cancel an abort?}

					{used to test for double-click}
					{-----------------------------}
   lastWasClick: boolean;		{was the last event a click?}
   clickWhen: longint;			{time of last click}
   clickH,clickV: integer;		{place of last click}

{-- Defined in assembly ----------------------------------------}

procedure TrackCursor (v,h,width,height: integer; redraw: boolean); extern;

{ change the cursor based on screen position			}
{								}
{ Parameters:							}
{    h,v - mouse position in local coordinates			}
{    width - width of screen, in characters			}
{    height - height of screen, in pixels			}
{    redraw - redraw the cursor, reguardless of knowledge of	}
{	need							}


procedure WakeUp; extern;

{ read initialization files (if any)				}

{-- Local subroutines ------------------------------------------}

function SpecialWindow (wp: grafPortPtr): boolean;

{ is the window one of our special windows?			}
{								}
{ Parameters:							}
{    wp - window to check					}
{								}
{ Returns: true if the window is special 			}

begin {SpecialWindow}
SpecialWindow :=
   (wp = frWPtr) 			{find/replace window}
   or (wp = grPtr)			{graphics window}
   or (wp = vrPtr);			{variables window}
end; {SpecialWindow}


function TextWindow (wp: grafPortPtr): boolean;

{ is the window one of our text (source) windows?		}
{								}
{ Parameters:							}
{    wp - window to check					}
{								}
{ Returns: true if the window is one of our text windows 	}

label 1;

var
   fp: buffPtr;				{pointer to a file record}

begin {TextWindow}
TextWindow := false;			{assume no match}
if currentPtr <> nil then		{make the file list accurate}
   currentPtr^ := currentFile;
fp := filePtr;				{scan the list of files for a match}
while fp <> nil do begin
   if fp^.wPtr = wp then begin
      TextWindow := true;
      goto 1;
      end; {if}
   fp := fp^.next;
   end; {while}
1:
end; {TextWindow}


function MyWindow(wp: grafPortPtr): boolean;

{ is the window one of our's?                                   }
{								}
{ Parameters:							}
{    wp - window to check					}
{								}
{ Returns: true if the window is one of ours			}

begin {MyWindow}
MyWindow := SpecialWindow(wp) or TextWindow(wp);
end; {MyWindow}


procedure MenuNew;

{ open and activate a new window 				}

var
   sPtr: pStringPtr;			{pointer to 'Untitled'}
   osptr: gsosInStringPtr;		{work pointer}
   osstr: gsosInString;			{work buffer}

begin {MenuNew}
sPtr := GetPString(104+base);
osptr := PStringToOSString(sPtr);
osstr := osptr^;
OpenNewWindow(0,25,640,175,@osstr);
lastUntitledNum := lastUntitledNum+1;
currentFile.fileName := concat(sPtr^, cnvis(lastUntitledNum));
osptr := PStringToOSString(@currentFile.fileName);
currentFile.pathname := osptr^;
currentFile.fileName := concat(' ', currentFile.fileName, ' ');
currentPtr^ := currentFile;
SetWTitle(@currentPtr^.fileName,currentFile.wPtr);
RemoveWindow(currentFile.wPtr);
AddWindow2(currentFile.wPtr);
FreePString(104+base);
end; {MenuNew}


procedure MenuSelectWindow (id: integer);

{ bring a selected window to front				}
{								}
{ Parameters:							}
{    id - menu ID						}

var
   wlp: windowMenuListPtr;		{work pointer}

begin {MenuSelectWindow}
wlp := windowMenuList;
while wlp <> nil do
   if id = wlp^.menuID then begin
      if FindActiveFile(wlp^.wPtr) or SpecialWindow(wlp^.wPtr) then begin
	 StartDrawing(wlp^.wPtr);
	 SelectWindow(wlp^.wPtr);
	 CheckWindow(wlp^.wPtr);
	 end; {if}
      wlp := nil;
      end {if}
   else
      wlp := wlp^.next;
end; {MenuSelectWindow}


procedure ChangeWindow(wp: grafPortPtr; left,top,width,height: integer);

{ change the position and size of a window			}
{								}
{ Parameters:							}
{    wp - window to change					}
{    left, top, width, height - new position, size		}

var
   disp: integer;			{temp variable}
   port: grafPortPtr;			{caller's grafPort}
   r: rect;				{new window rect}
   tbool: boolean;			{temp function result}

begin {ChangeWindow}
if left mod 8 <> 0 then begin
   disp := left mod 8;
   left := left-disp;
   width := width+disp;
   end; {if}
r.left := left;		r.right := r.left+width;
r.top := top;		r.bottom := r.top+height;
port := GetPort;
tbool := FindActiveFile(wp);
SetPort(wp);
ResizeWindow(true, r, wp);
EraseRect(r);
ChangeSize(width,height,false);
SetPort(port);
tbool := FindActiveFile(port);
end; {ChangeWindow}


procedure MenuStack;

{ Stack the windows on the desktop				}

const
   maxHeight = 187;			{height of desk}
   maxWidth = 640;			{width of desk}
   overlapX = 12;			{overlap in X direction}
   overlapY = 12;			{overlap in Y direction}
   top = 13;				{size of window title}

var
   height,width,wtop,wleft: integer;	{for computing window location,size}
   fw: grafPortPtr;			{front window}
   fp: buffPtr;				{file list pointer}
   i: integer;				{index variables}


   procedure Stack (fp: buffPtr);

   { Stack the windows, back to front				}
   {								}
   { Parameters: 						}
   {	fp - next window to stack				}

   begin {Stack}
   if fp <> nil then begin
      Stack(fp^.next);
      if fp^.wPtr <> fw then begin
	 ChangeWindow(fp^.wPtr,wleft,wtop+top,width,height);
	 wleft := wleft+overlapX;
	 wtop := wtop+overlapY;
	 if wleft+width- overlapX div 2 > maxWidth then begin
	    wtop := 12;
	    wleft := 0;
	    end; {if}
	 end; {if}
      end; {if}
   end; {Stack}


begin {MenuStack}
WaitCursor;				{use the watch cursor}
fw := FrontWindow;			{record the window that should be front}
i := 0;					{count the windows}
fp := filePtr;
while fp <> nil do begin
   i := i+1;
   fp := fp^.next;
   end; {while}
if i < 8 then begin			{decide on a height, width}
   width := maxWidth-(i-1)*overLapX;
   height := maxHeight-i*overlapY;
   end {if}
else begin
   width := maxWidth-6*overlapX;
   height := maxHeight-7*overlapY;
   end; {else}
wtop := 12; wleft := 0;			{size the back windows}
Stack(filePtr);
ChangeWindow(fw,wleft,wtop+top,width,height); {size the front window}
SelectWindow(fw);			{select the front window}
ResetCursor;				{back to system cursor}
end; {MenuStack}


procedure MenuTile;

{ Tile the windows on the desktop				}

const
   maxHeight = 187;			{height of desk}
   maxWidth = 640;			{width of desk}
   top = 13;				{size of window title}

var
   count: integer;			{number of windows}
   height,width,wtop,wleft: integer;	{for computing window location,size}
   fp: buffPtr;				{file list pointer}
   fw: grafPortPtr;			{front window}
   j: integer;				{index variable}

begin {MenuTile}
WaitCursor;				{use the watch cursor}
fw := FrontWindow;			{record the window that should be front}
count := 0;				{count the windows}
fp := filePtr;
while fp <> nil do begin
   fp := fp^.next;
   count := count+1;
   end; {while}
case count of				{decide on a height, width}
   1: begin
      height := maxHeight;
      width := maxWidth;
      end;
   2: begin
      height := maxHeight;
      width := maxWidth div 2;
      end;
   3,4: begin
      height := maxHeight div 2;
      width := maxWidth div 2;
      end;
   5,6: begin
      height := maxHeight div 3;
      width := maxWidth div 2;
      end;
   otherwise: begin
      height := maxHeight div 3;
      width := maxWidth div 3;
      end;
   end; {case}
wtop := 13; wleft := 0;			{size the windows}
fp := filePtr;
for j := 1 to count do begin
   ChangeWindow(fp^.wptr, wleft+1, wtop+top, width-2, height-top);
   wleft := wleft+width;
   if wleft > 640-width div 2 then begin
      wtop := wtop+height;
      if wtop > 200-height div 2 then
	 wtop := 13;
      wleft := 0;
      end; {if}
   fp := fp^.next;
   end; {for}
SelectWindow(fw);			{select the front window}
ResetCursor;				{back to system cursor}
end; {MenuTile}

{-- Externally available subroutines ---------------------------}

procedure CheckMenuItems;

{ check and uncheck file dependent menu items			}

var
   lp: languageRecPtr;			{loop variable}

begin {CheckMenuItems}
if currentPtr <> nil then begin
   with currentFile do begin
      CheckMItem(not insert,extras_OverStrike);
      CheckMItem(autoReturn,extras_AutoIndent);
      CheckMItem(showRuler,extras_ShowRuler);
      CheckMItem(profile,debug_Profile);
      CheckMItem(autoSave,extras_AutoSave);
      if undoList = nil then
	 DisableMItem(edit_undo)
      else
	 EnableMItem(edit_undo);
      CheckMItem(language = -1,languages_Shell);
      lp := languages;
      while lp <> nil do begin
	 CheckMItem(language = lp^.number,lp^.menuItem);
	 lp := lp^.next;
	 end; {while}
      end; {with}
   if currentFile.changed then
      EnableMItem(file_RevertToSaved)
   else
      DisableMItem(file_RevertToSaved);
   end; {if}
end; {CheckMenuItems}


procedure DoSaveAs (action: integer);

{ Save a file to a user-supplied name				}
{								}
{ Parameters:							}
{    action - FastFile action					}

label 1;

var
   fp: buffPtr;				{for checking file list for duplicates}
   reply: replyRecord5_0;		{reply from SFO}
   rhandle: handle;			{file path handle}
   rptr: gsosOutStringPtr;		{file path pointer}
   name: string33;			{file name with blanks stripped}

begin {DoSaveAs}
ResetCursor;
name := currentFile.fileName;
Delete(name,1,1);
Delete(name,length(name),1);
reply.nameVerb := 3;
reply.pathVerb := 3;
SFPutFile2(165, 40, 2, 105+base, 0, PStringToOSString(@name), reply);
Null0;
if reply.good <> 0 then begin
   fp := filePtr;			 {prevent duplications}
   rhandle := pointer(reply.pathref);
   HLock(rhandle);
   rptr := pointer(rhandle^);
   while fp <> nil do begin
      if fp <> currentPtr then
	 if OSStringsEqual(@fp^.pathName, @rptr^.theString) then begin
	    FlagError(24, 0);
	    goto 1;
	    end; {if}
       fp := fp^.next;
       end; {while}
   currentFile.changed := true;		 {set the name}
   currentFile.isFile := true;
   currentFile.pathName := rptr^.theString;
   rhandle := pointer(reply.nameref);
   HLock(rhandle);
   rptr := pointer(rhandle^);
   currentFile.fileName := concat(' ', OSStringToPString(@rptr^.theString)^, ' ');
   currentPtr^ := currentFile;
   SaveFile(action);
   SetWTitle(@currentPtr^.fileName,currentFile.wPtr);
   RemoveWindow(currentFile.wPtr);
   AddWindow2(currentFile.wPtr);
   end; {if}
1:
if reply.good <> 0 then begin
   DisposeHandle(handle(reply.nameRef));
   DisposeHandle(handle(reply.pathRef));
   end; {if}
end; {DoSaveAs}


procedure CloseCurrentWindow (var done: boolean; executing: boolean;
   action: integer);

{ close the active window					}
{								}
{ Parameters:							}
{    done - is this exit processing?				}
{    executing - are we executing a program?			}
{    action - FastFile action code				}

label 1;

const
   alertID = 3003;			{alert string resource ID}

var
   button: integer;			{alert button number}
   ffDCB: fastFileDCBGS;		{FastFile record}
   fw: grafPortPtr;			{pointer to front window}
   namePtr: ^string33;			{file name (for prompt)}
   purged: boolean;			{is the file purged? (or deleted)}
   tbool: boolean;			{temp boolean}

begin {CloseCurrentWindow}
fw := FrontWindow;			{find the correct window to close}
if MyWindow(fw) then begin
   if fw = frWPtr then begin		{find/replace window}
      CloseDialog(frWPtr);
      frWPtr := nil;
      end {if}
   else if fw = grPtr then begin	{graphics window}
      graphicsWindowOpen := false;
      DoGraphics;
      end {else if}
   else if fw = vrPtr then begin 	{variables window}
      CloseWindow(vrPtr);
      vrPtr := nil;
      end {else if}
   else begin				{current text window}
      RemoveWindow(fw);			{remove the window from the window list}
      tbool := FindActiveFile(fw);	{make the front window current}
      with currentFile do begin
	 purged := false;
	 if changed then begin		{see if we should save the file}
            ResetCursor;
            namePtr := @currentFile.fileName;
	    button := AlertWindow($0005, @namePtr, base + alertID);
	    if button = 0 then begin
	       if currentFile.isFile then
		  SaveFile(action)
	       else
		  DoSaveAs(action);
               if currentFile.changed then begin
	          AddWindow2(wPtr);
                  cancelButton := true;
                  end; {if}
	       if action = 7 then
		  purged := true;
	       end {if}
	    else if button = 2 then begin
	       AddWindow2(wPtr);
	       cancelButton := true;
	       goto 1;
	       end; {else}
	    end {if}
	 else if (action = 7) and currentFile.isFile then begin
	    DisposeHandle(pointer(buffHandle));
            ffDCB.pcount := 14;
	    ffDCB.action := 5;
	    ffDCB.pathName := @currentFile.pathName;
	    FastFileGS(ffDCB);
	    purged := true;
            end; {else if}
	 Undo_PopAll;			{dump the undo stack}
	 if not purged then		{dispose of the buffer area}
	    DisposeHandle(pointer(buffHandle));
	 CloseWindow(fw);
	 if last = nil then		{remove the file buffer from the list}
	    filePtr := next
	 else
	    last^.next := next;
	 if next <> nil then
	    next^.last := last;
	 end; {with}
      if currentPtr = sourcePtr then
	 sourcePtr := nil;
      dispose(currentPtr);		{dispose of the file buffer}
      currentPtr := nil;
      if filePtr <> nil then		{switch to another window}
	 tbool := FindActiveFile(filePtr^.wPtr);
      CheckMenuItems;
      end; {else}
   end {if}
else if GetSysWFlag(fw) then
   CloseNDAbyWinPtr(fw);
1:
end; {CloseCurrentWindow}


function FileQuit: boolean;

{ remove all windows and quit					}

var
   tbool: boolean;			{temp boolean}

begin {FileQuit}
cancelButton := false;
while (filePtr <> nil) and (not cancelButton) do
   CloseCurrentWindow(tbool, false, 7);
FileQuit := not cancelButton;
end; {FileQuit}


{$DataBank+}

procedure EditIntercept;

{ intercept handler for the EDIT command 			}

var
   giDCB: getLInfoDCBGS;			{get language info DCB}

begin {EditIntercept}
giDCB.pcount := 11;
lsFile.maxSize := osMaxSize;
ldFile.maxSize := osMaxSize;
lnamesList.maxSize := osMaxSize;
liString.maxSize := osMaxSize;
giDCB.sFile := @lsFile;
giDCB.dFile := @ldFile;
giDCB.namesList := @lnamesList;
giDCB.iString := @liString;
GetLInfoGS(giDCB);
OpenNewWindow(0,25,640,175,@lsFile.theString);
end; {EditIntercept}

{$DataBank-}


procedure SelectAll;

{ select the entire document					}

begin {SelectAll}
with currentFile do begin
   if gapStart = buffStart then
      cursor := pageStart
   else
      cursor := buffStart;
   cursorRow := -topLine;
   cursorColumn := 0;
   select := pointer(ord4(buffEnd)-1);
   selection := select <> cursor;
   DrawScreen;
   ShowCursor;
   end; {with}
end; {SelectAll}


procedure DoDeleteLine;

{ delete a line							}

var
   cc: integer;				{cursor column}
   lInsert: boolean;			{local insert mode flag}

begin {DoDeleteLine}
DeleteSelection;
with currentFile do begin
   cc := cursorColumn;
   MoveToStart;
   select := cursor;
   while select^ <> return do
      select := pointer(ord4(select)+1);
   select := pointer(ord4(select)+1);
   selection := true;
   lInsert := insert;
   insert := true;
   Key(chr(deleteCh));
   insert := lInsert;
   FindCursor;
   MoveRight(cc);
   DrawScreen;
   end; {with}
end; {DoDeleteLine}


procedure DoInsertLine;

{ insert a blank line in the file				}

var
   cc: integer;				{cursor column}
   insertMode,autoReturnMode: boolean;	{editor modes}

begin {DoInsertLine}
DeleteSelection;
with currentFile do begin
   FollowCursor; 			{move the screen to show the cursor}
   cc := cursorColumn;			{move to the start of the line}
   MoveLeft(cc);
   insertMode := insert; 		{insert a new line}
   insert := true;
   autoReturnMode := autoReturn;
   autoReturn := false;
   Key(chr(return));
   insert := insertMode;
   autoReturn := autoReturnMode;
   MoveRight(cc);			{move the cursor to the proper spot}
   MoveUp(1);
   DrawScreen;
   end; {with}
end; {DoInsertLine}


procedure DoJoinLines;

{ join the current line to the following one			}

var
   lInsert: boolean;			{local insert mode flag}
   r: rect;				{info bar rect}

begin {DoJoinLines}
disableScreenUpdates := true;
DeleteSelection;
with currentFile do begin
   lInsert := insert;
   insert := true;
   MoveLeft(cursorColumn);
   MoveDown(1);
   Key(chr(deleteCh));
   insert := lInsert;
   disableScreenUpdates := false;
   DrawScreen;
   FollowCursor;
   if showRuler then begin
      currentPtr^ := currentFile;
      StartInfoDrawing(r,wPtr);
      DrawRuler(r,ord4(@currentFile),wPtr);
      EndInfoDrawing;
      end; {if}
   SetCtlValue(leftColumn,hScroll);
   end; {with}
end; {DoJoinLines}


procedure DoShowRuler;

{ show or hide the ruler 					}
{								}
{ Notes: Declared externally in Buffer.pas			}

var
   i: integer;				{index variable}
   r: rect;				{original port rectangle}
   p: point;				{original window location}
   wp: grafPortPtr;			{work window pointers}

begin {DoShowRuler}
with currentFile do begin
   showRuler := not showRuler;		{flip ruler state}
   CheckMItem(showRuler,extras_ShowRuler);
   GetPortRect(r);			{get & update the size & location}
   p.v := 0; p.h := 0;
   LocalToGlobal(p);
   p.v := p.v-25;
   if showRuler then begin
      r.v2 := r.v2-infoHeight+1;
      p.v := p.v+infoHeight-1;
      end {if}
   else begin
      r.v2 := r.v2+infoHeight-1;
      p.v := p.v-infoHeight+1;
      end; {else}
   wp := wPtr;				{create a new frame}
   wPtr := NewWindowFrame(p.h,p.v,r.h2,r.v2,wp,showRuler,
      @currentPtr^.fileName);
   vScrollAlt := nil;
   vScroll := nil;
   hScroll := nil;
   grow := nil;
   SetInfoRefCon(ord4(currentPtr),wPtr);
   currentPtr^ := currentFile;
   SetInfoDraw(@DrawRuler,wPtr);
   SetContentDraw(@UpdateAWindow,wPtr); {set up the content routine}
   StartDrawing(wPtr);			{fix the size dependent stuff}
   ChangeSize(r.h2,r.v2,false);
   SelectWindow(wPtr);			{select the new window}
   RemoveWindow(wp);			{update the window menu}
   AddWindow2(wPtr);
   CloseWindow(wp);			{get rid of the old one}
   end; {with}
end; {DoShowRuler}


procedure DoZoom;

{ Zoom or unzoom a window, based on the window size		}

const
   zLeft = 0;				{zoom rect}
   zTop = 25;
   zBottom = 200;
   zRight = 640;
   infoHeight = 12;			{info bar height}

var
   r: rect;				{port rect}
   rPtr: rectPtr;			{returned by GetZoomRect}
   rzTop: integer;			{zTop with ruler accounted for}

begin {DoZoom}
SetPort(currentFile.wPtr);
if currentFile.showRuler then
   rzTop := zTop+infoHeight
else
   rzTop := zTop;
GetPortRect(r);
LocalToGlobal(r.topLeft);
LocalToGlobal(r.botRight);
if (r.left <> zLeft)
   or (r.right <> zRight)
   or (r.top <> rzTop)
   or (r.bottom <> zBottom) then begin
   SetZoomRect(r, currentFile.wPtr);
   r.left := zLeft;
   r.right := zRight;
   r.top := rzTop;
   r.bottom := zBottom;
   end {if}
else begin
   rPtr := GetZoomRect(currentFile.wPtr);
   r := rPtr^;
   end; {else}
ResizeWindow(true, r, currentFile.wPtr);
ChangeSize(r.h2-r.h1,r.v2-r.v1,false);
end; {DoZoom}


procedure DoKeyDown (var lastEvent: eventRecord);

{ handle a keyDown event 					}
{								}
{ Parameters:							}
{    lastEvent - event containing the keystroke			}
 
const
   upArrow     = $0B;			{key codes}
   downArrow   = $0A;
   leftArrow   = $08;
   rightArrow  = $15;
   chcomma     = $2C;
   chdot       = $2E;
   chlt	       = $3C;
   chgt	       = $3E;

var
   ch: integer;				{ord of character}
   lNumLines: longint;			{for checking for change in file length}
   oldSelection: boolean;		{was there a selection?}
   temp: longint;			{for moving screen}


   procedure RemoveSelection;

   { Makes sure any active selection is removed			}

   var
      temp: charPtr;			{for swaping cursor, select}

   begin {RemoveSelection}
   with currentFile do
      if selection then begin
	 if ord4(cursor) > ord4(select) then begin
	    temp := cursor;
	    cursor := select;
	    select := temp;
	    FindCursor;
	    end; {if}
	 selection := false;
	 FollowCursor;
	 DrawScreen;
	 ObscureCursor;
	 end; {if}
   end; {RemoveSelection}


begin {DoKeyDown}
with currentFile do begin
   ch := long(lastEvent.eventMessage).lsw & $FF;
   case ch of
      upArrow:	begin
		RemoveSelection;
		if lastEvent.eventModifiers & appleKey = 0 then
		   MoveUp(1)
		else begin
		   FollowCursor;
		   if cursorRow = 0 then
		      MoveUp(height)
		   else
		      MoveUp(long(cursorRow).lsw);
		   end; {else}
		end;
      downArrow: begin
		RemoveSelection;
		if lastEvent.eventModifiers & appleKey = 0 then
		   MoveDown(1)
		else begin
		   FollowCursor;
		   if cursorRow = height-1 then
		      MoveDown(height)
		   else
		      MoveDown(height-1-long(cursorRow).lsw);
		   end; {else}
		end;
      leftArrow: begin
		RemoveSelection;
		if lastEvent.eventModifiers & appleKey <> 0 then begin
		   FollowCursor; 		{move to col 0}
		   Position(0,long(cursorRow).lsw);
		   end {if}
		else if lastEvent.eventModifiers & optionKey <> 0 then
		   WordTabLeft			{move to start of last word}
		else
		   MoveLeft(1);			{move left 1 col}
		end;
      rightArrow: begin
		RemoveSelection;
		if lastEvent.eventModifiers & appleKey <> 0 then begin
		   FollowCursor; 		{move to eol}
		   Position(0,long(cursorRow).lsw);
		   while cursor^ <> return do
                      cursor := pointer(ord4(cursor)+1);
		   cursorColumn := FindCursorColumn;
		   FollowCursor;
		   end {if}
		else if lastEvent.eventModifiers & optionKey <> 0 then
		   WordTabRight			{move to start of next word}
		else
		   MoveRight(1); 		{move right 1 col}
		end;
      $31,$32,$33,$34,$35,$36,$37,$38,$39:	{numeric keys}
		if lastEvent.eventModifiers & appleKey <> 0 then begin
		   Position(0,0);
		   if ch = ord('9') then
		      temp := numLines-height+1-topLine
		   else
		      temp := (numLines >> 3)*(ch-$31) - topLine;
		   if temp > 0 then
		      ScrollDown(temp)
		   else
		      ScrollUp(-temp);
		   if ch = ord('9') then begin
		      temp := numLines-topLine-1;
		      Position(0,long(temp).lsw);
		      while cursor^ <> return do
                	 MoveRight(1);
		      end {if}
		   else
		      Position(0,0);
		   end {if}
		else begin
		   Key(chr(ch));
		   DrawLine(long(currentFile.cursorRow).lsw);
		   end; {else}
      tab:	TabChar(lastEvent.eventModifiers & appleKey <> 0);
      return,deleteCh:
		with currentFile do begin
		   oldSelection := selection;
		   lNumLines := numLines;
		   if (ch = return)
		      and ((lastEvent.eventModifiers & keyPad <> 0)
		      or (language = -1)) then
		      ExecuteSelection
		   else
		      Key(chr(ch));
		   if (numLines = lNumLines) and not oldSelection then
		      DrawLine(long(currentFile.cursorRow).lsw)
		   else
		      DrawScreen;
		   end; {with}
      otherWise:
                if ord(ch) in [$11..$14, ord(' ')..ord('~'), $80..$D8, $DE, $DF]
                   then begin
		   Key(chr(ch));
		   {note: Key puts cursor on screen}
		   DrawLine(long(currentFile.cursorRow).lsw);
		   end; {if}
      end; {case}
   end; {with}
end; {DoKeyDown}


procedure Events {lastEvent: eventRecord; event: integer;
  var done: boolean; executing: boolean};

{ handle the main event loop					}
{								}
{ Parameters:							}
{    lastEvent - event record					}
{    event - event number					}
{    done -							}
{    executing - is a program executing? 			}

const
   onTime	 = 20;			{heartbeats for cursor flash timing}
   offTime	 = 10;
 
   appleKey	 = $0100;		{key modifiers}
   optionKey	 = $0800;
   shiftKey	 = $0200;
   keyPad	 = $2000;

var
   dPtr: grafPortPtr;			{dialog grafPortPtr (from DialogSelect)}
   elapsed: longint;			{# hearbeats since last blink}
   fw: grafPortPtr;			{front window work pointer}
   i: integer;				{loop variable}
   isSysWindow: boolean; 		{is the front window a system window?}
   itemHit: integer;			{dialog item hit (from DialogSelect)}
   lp: languageRecPtr;			{loop variable}
   p: point;				{work point for coordinate transforms}
   port: grafPortPtr;			{caller's grafport}
   qtDCB: quitOSDCB;			{DCB for exiting program early}
   r: rect;				{info bar rectangle}
   tbool: boolean;			{temp boolean}


   procedure DoContent;

   { Handle a mouse down event in the content region		}
 
   const
      minHeight	  = 50;			{min height of special windows}
 
   var
      part: integer;			{part # returned by FindControl}
      ctl: ctlRecHndl;			{control handle}
      p: point;				{work variable}
      wp: grafPortPtr;			{pointer to selected window}


      procedure UpdateLeftColumn;

      { do all updates required after a change to leftColumn	}
  
      var
	 r: rect;			{info bar rect}
  
      begin {UpdateLeftColumn}
      with currentFile do begin
	 if showRuler then begin
	    currentPtr^ := currentFile;
	    StartInfoDrawing(r,wPtr);
	    DrawRuler(r,ord4(@currentFile),wPtr);
	    EndInfoDrawing;
	    end; {if}
	 SetCtlValue(leftColumn,hScroll);
	 DrawScreen;
	 end; {with}
      end; {UpdateLeftColumn}


      procedure DoGrowBox (wp: grafPortPtr);

      { grow the current window					}
      {								}
      { Parameters:						}
      {	   wp - window to grow					}
  
      var
	 r: rect;			{port rectange}
	 s: record			{for converting integers}
	    case boolean of
	       true:  (long: longint);
	       false: (lsw,msw: integer);
	    end;
	 oldPort: grafPortPtr;		{current grafPort ptr}
  
      begin {DoGrowBox}
      with lastEvent.eventWhere do	{track the growing of the window}
	 s.long := GrowWindow(24,23,h,v,wp);
      if s.long <> 0 then		{if the size changed then...}
	 if wp = grPtr then begin	{graphics window gets special treatment}
	    SizeWindow(s.msw,s.lsw,grPtr);
	    UpdateGrWindow;
	    end {if}
	 else if SpecialWindow(wp) then begin
	    StartDrawing(wp);		{start drawing in the special window}
	    if wp = vrPtr then		{make suer var window is wide enough}
	       if s.msw < 200 then
		  s.msw := 200;
					{be sure we leave a min height}
	    if s.lsw < minHeight then s.lsw := minHeight;
	    SizeWindow(s.msw,s.lsw,wp); {update the size}
	    RedoVRWindow;
	    end {else if}
	 else begin
	    oldPort := GetPort;		{change a text window...}
	    SetPort(wp);
	    tbool := FindActiveFile(wp);
	    ChangeSize(s.msw,s.lsw,false);
	    SetPort(oldPort);
	    tbool := FindActiveFile(oldPort);
	    end; {else}
      end; {DoGrowBox}


      procedure DoScroll (ctl: ctlRecHndl; wp: grafPortPtr; part, v: integer);

      { handle scrolls						}
      {								}
      { Parameters:						}
      {	   ctl - scroll bar					}
      {	   wp - window containing the control			}
      {	   part - selected part code				}
      {	   v - vertical disp (for split screen check)		}
  
      var
	 doPause: boolean;		{do we need to pause?}
	 lc: integer;			{local left column}
	 oCtl: ctlRecHndl;		{original control handle}
	 part2: integer; 		{part # from TrackControl}
	 port: grafPortPtr;		{current grafPort ptr}
	 tl: longint;			{local top line number}


	 procedure Pause (time: integer);

	 { Pause for a while					}
	 {							}
	 { Parameters:						}
	 {    time - # heartbeats to pause			}

	 var
	    startTime: longint;		{startint tickCount}

	 begin {Pause}
	 startTime := TickCount;
	 while TickCount-startTime < time do {nothing};
	 end; {Pause}


	 procedure CheckForScroll (lc: integer);

	 { see if horizontal scrolling is required		}
	 {							}
	 { Parameters:						}
	 {    lc -						}
   
	 begin {CheckForScroll}
	 with currentFile do
	    if wp = wPtr then begin
	       if lc < 0 then lc := 0;	{make sure it is in range}
	       if lc > 255-width then lc := 255-width;
	       if lc <> leftColumn then begin
		  leftColumn := lc;	{set the column}
		  UpdateLeftColumn;
		  end; {if}
	       end; {if}
	 end; {CheckForScroll}


      begin {DoScroll}
      port := nil;			{make sure the correct window is active}
      if not SpecialWindow(wp) then
	 if wp <> currentFile.wPtr then begin
	    port := GetPort;
	    tbool := FindActiveFile(wp);
	    end; {if}
      with currentFile do begin
	 if wp = wPtr then		{if needed, swap active half of window}
	    if splitScreen then
	       if (ctl = vScroll) or (ctl = vScrollAlt) then
		  if dispFromTop = 0 then begin
		     if (v > dispFromTopAlt) and (v < maxHeight) then
			SwitchSplit;
		     end {if}
		  else begin
		     if (v < dispFromTop) and (v >= 0) then
			SwitchSplit;
		     end; {else}
	 if part in [7,8] then begin	{if the part is a page area...}
	    HiliteControl(part,ctl);
	    oCtl := ctl;
	    part2 := part;
	    doPause := true;
	    repeat
	       if part = part2 then
		  if ctl = hScroll then begin
		     if part = 7 then
			lc := leftColumn-width {handle left page}
		     else if part = 8 then
			lc := leftColumn+width; {handle right page}
		     if part <> 0 then
			CheckForScroll(lc);
		     end {if}
		  else begin
		     if wp = vrPtr then
			DoVariablesScroll(part)
		     else
			if part = 7 then
			   ScrollUp(height)   {handle up page}
			else if part = 8 then
			   ScrollDown(height); {handle down page}
		     end; {else}
	       if doPause then begin
		  doPause := false;
		  Pause(6);
		  end; {if}
	       if GetNextEvent($076E,lastEvent) then ;
	       with lastEvent.eventWhere do
		  part2 := FindControl(ctl,h,v,wp);
	    until lastEvent.eventWhat = mouseUpEvt;
	    HiliteControl(0,octl);
	    end {if}
	 else if part in [5,6] then	{if the part is not the slide switch...}
	    begin
	    HiliteControl(part,ctl);
	    oCtl := ctl;
	    part2 := part;
	    doPause := true;
	    repeat
	       if part = part2 then
		  if ctl = hScroll then begin
		     if part = 5 then
			lc := leftColumn-1 {handle left arrow}
		     else if part = 6 then
			lc := leftColumn+1; {handle right arrow}
		     if part <> 0 then
			CheckForScroll(lc);
		     end {if}
		  else begin
		     if wp = vrPtr then
			DoVariablesScroll(part)
		     else
			if part = 5 then
			   ScrollUp(1)	{handle up arrow}
			else if part = 6 then
			   ScrollDown(1); {handle down arrow}
		     end; {else}
	       if doPause then begin
		  doPause := false;
		  Pause(6);
		  end; {if}
	       if GetNextEvent($076E,lastEvent) then ;
	       with lastEvent.eventWhere do
		  part2 := FindControl(ctl,h,v,wp);
	    until lastEvent.eventWhat = mouseUpEvt;
	    HiliteControl(0,oCtl);
	    end {else}
	 else if part = 129 then 	{reposition based on new thumb loc.}
	    begin
	    with lastEvent.eventWhere do
	       part := TrackControl(h,v,pointer(-1),ctl);
	    if ctl = hScroll then begin
	       lc := GetCtlValue(hScroll);
	       if lc <> leftColumn then begin
		  leftColumn := lc;
		  UpdateLeftColumn;
		  end;
	       end {if}
	    else begin
	       if wp = vrPtr then
		  DoVariablesScroll(part)
	       else begin
		  tl := GetCtlValue(vScroll);
		  if tl < topLine then
		     ScrollUp(topLine-tl)
		  else if tl <> topLine then
		     ScrollDown(tl-topLine);
		  end {else}
	       end; {else}
	    end; {else}
	 end; {with}
      if port <> nil then		{restore port on entry}
	 tbool := FindActiveFile(port);
      ShowCursor;
      end; {DoScroll}


      procedure DoMouseDown (pv: integer);

      { handle positioning the cursor and selections		}
      {								}
      { Parameters:						}
      {	   pv - pixel disp of initial selection			}
  
      label 1;
  
      type
	 selectType = (charSelect,wordSelect,lineSelect);
  
      var
	 h,v: integer;			{character location #}
	 min,max: charPtr;		{old selection range}
	 oldSelection: boolean;		{was there an old selection?}
	 p: point;			{lastEvent.eventWhere in local coords}
	 pivotMin,pivotMax: charPtr;	{pivot for contracing selections}
 
 
	 procedure DoSplitScreen;
 
	 { handle movement of split control & subsequent 	}
	 { splitting of screen					}
   
	 var
	    v: integer;			{current vertical position of control}
	    r: rect;			{current split screen rect}
	    p: point;			{mouse location in local coords}
	    pr: rect;			{current port rect}
    
	    procedure DrawSplit (var r: rect; v: integer);
 
	    { draw the screen split control at V 		}
	    {							}
	    { Parameters:					}
	    {	 r - split screen control rect			}
	    {	 v - new location				}
    
	    begin {DrawSplit}
	    r.v1 := v-2;
	    r.v2 := v+2;
	    SetSolidPenPat(whitePen);
	    PaintRect(r);
	    SetSolidPenPat(purplePen);
	    MoveTo(0,v);
	    LineTo(r.h2-1,v);
	    end; {DrawSplit}
    
	 begin {DoSplitScreen}
	 with currentFile do begin
	    r := splitScreenRect;	{set global variables}
	    GetPortRect(pr);
	    SetPenMode(2);
	    p := lastEvent.eventWhere;	{switch to local coordinates}
	    GlobalToLocal(p);
	    v := p.v;			{draw the original control}
	    DrawSplit(r,v);
	    repeat			{process events 'til mouse up}
	       if GetNextEvent($076E,lastEvent) then ;
	       event := lastEvent.eventWhat;
	       p := lastEvent.eventWhere; {switch to local coordinates}
	       GlobalToLocal(p);
					{keep the control on the screen}
	       with p do begin
		  if v < 0 then v := 0;
		  if v > pr.v2-hScrollHeight then v := pr.v2-hScrollHeight;
		  end; {with}
	       if v <> p.v then begin
		  DrawSplit(r,v);	{move the new control}
		  v := p.v;
		  DrawSplit(r,v);
		  end; {if}
	    until event = mouseUpEvt;
	    DrawSplit(r,v);		{erase the split screen control}
	    end; {with}
	 SplitTheScreen(v,pr);		{split the screen}
	 end; {DoSplitScreen}
 
 
	 procedure ExtendSelection;
 
	 { extend a previous selection (or cursor) to include	}
	 { the new one						}
   
	 begin {ExtendSelection}
	 with currentFile do begin
					{extend the selected area}
	    if ord4(cursor) > ord4(min) then
	       cursor := min
	    else if ord4(select) < ord4(max) then
	       select := max;
	    FindCursor;			{fix cursor variables}
	    selection := cursor <> select; {mark the selection}
	    end; {with}
	 end; {ExtendSelection}
 
   
	 procedure GetLocation (var h,v: integer);
 
	 { convert global mouse position to row, column		}
	 {							}
	 { Parameters:						}
	 {    h,v - row, column					}

	 var
	    p: point;			{work point}
   
	 begin {GetLocation}
	 p := lastEvent.eventWhere;
	 GlobalToLocal(p);
	 h := (p.h+2) div chWidth - 1;
	 if p.v < 0 then
	    v := -1
	 else
	    v := (p.v-currentFile.dispFromTop) div chHeight;
	 end; {GetLocation}
 
 
	 function InTextRegion (h,v: integer): boolean;
 
	 { is the position on the text part of the screen?	}
	 {							}
	 { Parameters:						}
	 {    h,v - position					}
	 {							}
	 { Returns: true if in text area, else false		}
   
	 begin {InTextRegoin}
	 with currentFile do
	    InTextRegion := (h <= width) and (v >= 0) and (v < height)
	       and (h >= 0);
	 end; {InTextRegoin}
 
 
	 function InLineSelectRegion (h,v: integer): boolean;
 
	 { is the position just to the left of the text part of }
	 { the window?						}
	 {							}
	 { Parameters:						}
	 {    h,v - position					}
	 {							}
	 { Returns: true if in line select area, else false	}
   
	 begin {InLineSelectRegoin}
	 with currentFile do
	    InLineSelectRegion := (h = -1) and (v >= 0) and (v < height);
	 end; {InLineSelectRegoin}
 
 
	 function DoubleClick (h,v: integer): boolean;
 
	 { is this a double click?				}
	 {							}
	 { Parameters:						}
	 {    h,v - position					}
	 {							}
	 { Returns: true if double-click, else false		}
   
	 begin {DoubleClick}
	 DoubleClick := false;
	 if (h = clickH) and (v = clickV) and lastWasClick
	    and (lastEvent.eventWhen-clickWhen <= GetDBLTime) then begin
	    DoubleClick := true;
	    lastWasClick := false;
	    end; {if}
	 end; {DoubleClick}
 
	   
	 procedure SaveSelection;
 
	 { save the current selection information		}
   
	 begin {SaveSelection}
	 with currentFile do begin
	    oldSelection := selection;
	    if not selection then
	       select := cursor;
	    if ord4(cursor) < ord4(select) then begin
	       min := cursor;
	       max := select;
	       end {if}
	    else begin
	       min := select;
	       max := cursor;
	       end; {else}
	    end; {with}
	 end; {SaveSelection}
 
   
	 procedure SetPivot;
 
	 { make the current selection the pivot selection	}
   
	 begin {SetPivot}
	 with currentFile do begin
	    if not selection then
	       select := cursor;
	    if ord4(cursor) < ord4(select) then begin
	       pivotMin := cursor;
	       pivotMax := select;
	       end {if}
	    else begin
	       pivotMin := select;
	       pivotMax := cursor;
	       end; {else}
	    end; {with}
	 end; {SetPivot}
 
 
	 procedure SelectWord (h,v: integer);
 
	 { select the current word				}
	 {							}
	 { Parameters:						}
	 {    h,v - position					}

	 var
            alphaChars: set of 0..255;	{characters that start a word selection}
            alphaNumChars: set of 0..255; {characters in a word selection}
	    done: boolean;		{loop termination}
	    lCursor: charPtr;		{used to make sure we get the right word}
            whiteSpace: set of 0..255;	{whitespace characters}

	 begin {SelectWord}
	 with currentFile do begin
	    disableScreenUpdates := true;
	    Position(h+leftColumn,v);
	    disableScreenUpdates := false;
	    if not (cursor^ in [return,tab,space]) then begin
	       lCursor := cursor;
	       cursor := pointer(ord4(cursor)+1);
	       WordTabLeft;
	       done := false;
               alphaChars := [ord('a')..ord('z'), ord('A')..ord('Z'),
                              ord('_'), ord('~'), $80..$9F, $A7, $AE, $AF,
                              $B4..$BF, $C4, $C6, $CB..$CF, $D8, $DE,$DF];
               alphaNumChars := alphaChars + [ord('0')..ord('9')];
               whiteSpace := [tab,return,space,$CA];
	       repeat
		  select := cursor;
		  if cursor^ in alphaChars then begin
		     while select^ in alphaNumChars do
			select := pointer(ord4(select)+1);
		     if ord4(select) > ord4(lCursor) then
			done := true
		     else
			cursor := select;
		     end {if}
		  else if chr(cursor^) in ['0'..'9'] then begin
		     while chr(select^) in ['0'..'9'] do
			select := pointer(ord4(select)+1);
		     if chr(select^) in ['.','e','E'] then begin
			if chr(select^) = '.' then begin
			   select := pointer(ord4(select)+1);
			   while chr(select^) in ['0'..'9'] do
			      select := pointer(ord4(select)+1);
			   end; {if}
			if chr(select^) in ['e','E'] then begin
			   select := pointer(ord4(select)+1);
			   if chr(select^) in ['+','-'] then
			      select := pointer(ord4(select)+1);
			   while chr(select^) in ['0'..'9'] do
			      select := pointer(ord4(select)+1);
			   end; {if}
			end; {if}
		     if ord4(select) > ord4(lCursor) then
			done := true
		     else
			cursor := select;
		     end {else if}
		  else begin
		     while not (select^ in alphaNumChars + whiteSpace) do
			select := pointer(ord4(select)+1);
		     end; {else}
		  if ord4(select) > ord4(lCursor) then
		     done := true
		  else
		     cursor := select;
	       until done;
	       selection := true;
	       end {if}
	    else begin
	       cursor := pointer(ord4(cursor)+1);
	       WordTabLeft;
	       while not (cursor^ in whiteSpace) do
		  cursor := pointer(ord4(cursor)+1);
	       select := cursor;
	       while select^ in whiteSpace do
		  select := pointer(ord4(select)+1);
	       end; {else}
	    selection := true;
	    end; {with}
	 end; {SelectWord}
 
 
	 procedure SelectLine (v: integer);
 
	 { select the line indicated by the vertical position v }
	 {							}
	 { Parameters:						}
	 {    v - position					}
 
	 begin {SelectLine}
	 with currentFile do begin
	    disableScreenUpdates := true;
	    Position(leftColumn,v);
	    disableScreenUpdates := false;
	    MoveToStart;
	    select := cursor;
	    while select^ <> return do
	       select := pointer(ord4(select)+1);
	    select := pointer(ord4(select)+1);
	    selection := true;
	    end; {with}
	 end; {SelectLine}
 
 
	 procedure DoChangeTab (h: integer);
 
	 { create/remove a tab stop				}
	 {							}
	 { Parameters:						}
	 {    h - position					}
   
	 begin {DoChangeTab}
	 with currentFile do begin
					{flip the tab stop}
	    ruler[h+leftColumn] := ruler[h+leftColumn]!1;
					{draw it}
	    DrawTabStop(h,ruler[h+leftColumn]);
	    DrawScreen;
	    end; {with}
	 end; {DoChangeTab}
 
   
	 procedure DragSelection (selectKind: selectType; h,v: integer);
 
	 { handle dragging a selection to extend it		}
	 {							}
	 { Parameters:						}
	 {    selectKind - tye of selection, e.g. line select	}
	 {    h,v - position					}
   
	 var
	    h2,v2: integer;		{character location #}
 
 
	    procedure CheckForScroll (var h1,v1: integer; h2,v2: integer);
  
	    { if a scroll is needed, do it			}
	    {							}
	    { Parameters:					}
	    {	 h1,v1 - 					}
	    {	 h2,v2 - 					}
    
	    var
	       gapSize: longint; 	{size of the gap}
	       checkMin,checkMax: boolean; {do we need to check for scroll?}
    
	    begin {CheckForScroll}
	    with currentFile do begin
					{don't flash the screen}
	       disableScreenUpdates := true;
					{check for scroll left}
	       if (h2 < 0) and (leftColumn > 0) then begin
		  h1 := h1+1;
		  leftColumn := leftColumn-1;
		  UpdateLeftColumn;
		  end; {if}
					{check for scroll right}
	       if (h2 >= width) and (leftColumn+width < 255) then begin
		  h1 := h1-1;
		  leftColumn := leftColumn+1;
		  UpdateLeftColumn;
		  end; {if}
					{compute the gap size}
	       gapSize := ord4(pageStart)-ord4(gapStart);
					{check for scroll up}
	       if (v2 < 0) and (topLine > 0) then begin
		  v1 := v1+1;
		  checkMax := ord4(pivotMax) < ord4(gapStart);
		  checkMin := ord4(pivotMin) < ord4(gapStart);
		  ScrollUp(1);
		  if checkMax then
		     if ord4(pivotMax) >= ord4(gapStart) then
			pivotMax := pointer(ord4(pivotMax)+gapSize);
		  if checkMin then
		     if ord4(pivotMin) >= ord4(gapStart) then
			pivotMin := pointer(ord4(pivotMin)+gapSize);
		  end; {if}
					{check for scroll down}
	       if (v2 >= height) and (topLine+height < numLines) then begin
		  v1 := v1-1;
		  checkMax := ord4(pivotMax) >= ord4(pageStart);
		  checkMin := ord4(pivotMin) >= ord4(pageStart);
		  ScrollDown(1);
		  if checkMax then
		     if ord4(pivotMax) < ord4(pageStart) then
			pivotMax := pointer(ord4(pivotMax)-gapSize);
		  if checkMin then
		     if ord4(pivotMin) < ord4(pageStart) then
			pivotMin := pointer(ord4(pivotMin)-gapSize);
		  end; {if}
	       disableScreenUpdates := false;
	       end; {with}
	    end; {CheckForScroll}

	 begin {DragSelection}
	 DrawScreen;
	 ShowCursor;
	 with currentfile do
	    repeat
					{get the next event}
	       if GetNextEvent($076E,lastEvent) then ;
	       event := lastEvent.eventWhat;
	       GetLocation(h2,v2);	{see where it happened}
	       CheckForScroll(h,v,h2,v2); {scroll if necessary}
	       if ((h2 <> h) and (selectKind <> lineSelect))
		  or (v2 <> v) then begin
		  h := h2;		{force h, v onto screen}
		  if h < 0 then h := 0;
		  if h >= width then h := width-1;
		  v := v2;
		  if v < 0 then v := 0;
		  if v >= height then v := height-1;
		  min := pivotMin;	{record the pivot for extension}
		  max := pivotMax;
					{select the new stuff}
		  if selectKind = charSelect then begin
		     disableScreenUpdates := true;
		     Position(h+leftColumn,v);
		     disableScreenUpdates := false;
		     select := cursor;
		     end {if}
		  else if selectKind = wordSelect then
		     SelectWord(h,v)
		  else {if selectKind = lineSelect then}
		     SelectLine(v);
		  ExtendSelection;	{combine the two selections}
		  DrawScreen;		{redraw the screen}
		  ShowCursor;
		  end; {if}
	    until event = mouseUpEvt;
	 end; {DragSelection}
 
   
	 procedure CheckSplit (v: integer);
 
	 { If needed, swap the active portion of the split	}
	 { screen.						}
	 {							}
	 { Parameters:						}
	 {    v - vertical disp in the window			}
 
	 begin {CheckSplit}
	 with currentFile do		  {if needed, swap active half of window}
	    if wp = wPtr then
	       if splitScreen then
		  if dispFromTop = 0 then begin
		     if (v > dispFromTopAlt) and (v < maxHeight) then
			SwitchSplit;
		     end {if}
		  else begin
		     if (v < dispFromTop) and (v >= 0) then
			SwitchSplit;
		     end; {else}
	 end; {CheckSplit}


      begin {DoMouseDown}
      HideCursor;
      with currentFile do begin
	 GetLocation(h,v);
	 {--- split screen ---}
	 p := lastEvent.eventWhere;
	 GlobalToLocal(p);
	 if PtInRect(p,splitScreenRect) then
	    DoSplitScreen
	 {--- disable other operations if executing ---}
	 else if executing then
	    goto 1
	 else begin
	    CheckSplit(pv);		{if needed, switch the split}
	    GetLocation(h,v);
	    {--- set or clear a tab stop ---}
	    if v < 0 then
	       DoChangeTab(h)
	    {--- select text ---}
	    else if InTextRegion(h,v) then begin
	       if DoubleClick(h,v)	{handle double clicks}
		  then begin		{extend a selection to a selected word}
		  if lastEvent.eventModifiers & shiftKey <> 0 then begin
		     SaveSelection;
		     SetPivot;
		     SelectWord(h,v);
		     ExtendSelection;
		     end {if}
		  else begin		{select a word}
		     selection := false;
		     SelectWord(h,v);
		     SetPivot;
		     end; {else}
					{handle dragging a selection}
		  DragSelection(wordSelect,h,v);
		  end {if}
	       else begin {not double click}
					{extend a selection to the current char}
		  lastWasClick := true;
		  if lastEvent.eventModifiers & shiftKey <> 0 then begin
		     SaveSelection;
		     SetPivot;
		     disableScreenUpdates := true;
		     Position(h+leftColumn,v);
		     disableScreenUpdates := false;
		     select := cursor;
		     ExtendSelection;
		     end {if}
		  else begin		{position the cursor}
		     Position(h+leftColumn,v);
		     selection := false;
		     SetPivot;
		     end; {else}
					{drag select to a char boundary}
		  DragSelection(charSelect,h,v);
		  end; {else}
	       end {if}
	    {--- line selections ---}
	    else if InLineSelectRegion(h,v) then begin
					{select all if option key down}
	       if lastEvent.eventModifiers & appleKey <> 0 then begin
		  SelectAll;
		  DrawScreen;
		  end {if}
	       else begin
					{extend selection to this line}
		  if lastEvent.eventModifiers & shiftKey <> 0 then begin
		     SaveSelection;
		     SetPivot;
		     SelectLine(v);
		     ExtendSelection;
		     end {if}
		  else begin		{select the line}
		     selection := false;
		     SelectLine(v);
		     SetPivot;
		     end; {else}
					{drag select by lines}
		  DragSelection(lineSelect,h,v);
		  end; {if}
	       end; {else}
	    end; {else}
	 end; {with}
      clickH := h;
      clickV := v;
      1:
      ShowCursor;
      end; {DoMouseDown}

   begin {DoContent}
   wp := pointer(lastEvent.taskData);
   if FrontWindow = wp then begin
      p := lastEvent.eventWhere;
      GlobalToLocal(p);
      with lastEvent.eventWhere do
	 part := FindControl(ctl,h,v,wp);
      if part = 10 then			{handle grow box}
	 DoGrowBox(wp)
      else if part <> 0 then		{handle scroll bars}
	 DoScroll(ctl,wp,part,p.v)
      else if wp = vrPtr then begin	{handle special windows}
	 if executing then begin
	    StartDrawing(wp);
	    DoVariablesMouseDown(p.h,p.v);
	    end; {if}
	 end {else}
      else if wp <> grPtr then		{handle event in content}
	 DoMouseDown(p.v);
      end; {if}
   end; {DoContent}


   procedure DoMenu;

   { Handle a menu event					}

   const
      alertID = 3004;			{alert string resource ID}

      procedure MenuAbout;

      { show about alert box					}

      const
	 alertID = 3002;		{alert string resource ID}

      var
	 button: integer;		{button pushed}

      begin {MenuAbout}
      ResetCursor;
      button := AlertWindow($0005, nil, base + alertID);
      end; {MenuAbout}


      procedure MenuClose;

      { Close a graphics window					}

      begin {MenuClose}
      CloseCurrentWindow(done,executing,7);
      if (FrontWindow = nil) or (FrontWindow <> currentFile.wPtr) then
         ResetCursor;
      end; {MenuClose}


      procedure MenuGraphics;

      { Show the graphics window				}

      begin {MenuGraphics}
      if graphicsWindowOpen then
         SelectWindow(grPtr)
      else begin
         graphicsWindowOpen := true;
         DoGraphics;
         end; {else}
      end; {MenuGraphics}


      procedure MenuOpen;

      { allow the user to select an existing file to open	}

      const
	 posX = 80;			{X position of the dialog}
	 posY = 50;			{Y position of the dialog}
	 titleID = 102;			{prompt string resource ID}

      var
	 ch: char;			{temp char}
	 fileTypes: typeList5_0;	{list of valid file types}
	 fName: pString;		{string path name}
	 i: 0..maxNameLen;		{loop/index pointer}
	 osNamePtr: gsosOutStringPtr;	{path pointer}
	 osNameHandle: ^gsosOutStringPtr; {path handle}
	 reply: replyRecord5_0;		{reply record}

      begin {MenuOpen}
      with fileTypes do begin		{set up the allowed file types}
	 numEntries := 2;
	 with fileAndAuxTypes[1] do begin
	    flags := $8000;
	    fileType := SRC;
	    end; {with}
	 with fileAndAuxTypes[2] do begin
	    flags := $8000;
	    fileType := TXT;
	    end; {with}
	 end; {with}
      reply.nameVerb := 3;		{get the file to open}
      reply.pathVerb := 3;
      SFGetFile2(posX, posY, 2, base + titleID, nil, fileTypes, reply);
      Null0;
      if ToolError <> 0 then
	 FlagError(3, ToolError)	{handle an error}
      else if reply.good <> 0 then	{open the file}
         begin
         HLock(handle(reply.pathref));
	 osNameHandle := pointer(reply.pathRef);
	 osNamePtr := osNameHandle^;
	 if osNamePtr^.theString.size <= osBuffLen then
            OpenNewWindow(0,25,640,175,@osNamePtr^.theString)
         else
            FlagError(1, 0);
					{dispose of the name buffers}
	 DisposeHandle(handle(reply.nameRef));
	 DisposeHandle(handle(reply.pathRef));
	 end; {else if}
      end; {MenuOpen}       


      procedure MenuShell;

      { Create or find a shell window				}

      begin {MenuShell}
      GetShellWindow;
      if FindActiveFile(shellPtr^.wPtr) then begin
	 StartDrawing(shellPtr^.wPtr);
	 SelectWindow(shellPtr^.wPtr);
	 CheckWindow(shellPtr^.wPtr);
	 end; {if}
      end; {MenuShell}


   begin {DoMenu}
   lastWasClick := false;
   if cursorVisible then Blink;
   case long(lastEvent.taskData).lsw of
      apple_About:	MenuAbout;

      file_New:		MenuNew;
      file_Open:	MenuOpen;
      file_Close:	MenuClose;
      file_Save:	if currentFile.isFile then
			   SaveFile(6)
			else
			   DoSaveAs(6);
      file_SaveAs:	DoSaveAs(6);
      file_RevertToSaved:
			with currentFile do begin
			   DisposeHandle(handle(buffHandle));
			   if LoadFile(@pathName) then begin
                              LoadFileStateResources(@pathName);
			      DrawScreen;
			      SetCtlParams(max2(numLines+height),height,
				 vScroll);
			      SetCtlValue(max2(topLine),vScroll);
			      if splitScreen then begin
				 SetCtlParams(max2(numLines+heightAlt),
				    heightAlt,vScrollAlt);
				 if height >= numLines then
				    topLineAlt := numLines-1
				 else
				    topLineAlt := height;
				 SetCtlValue(max2(topLineAlt),vScrollAlt);
				 end; {if}
			      SetCtlValue(leftColumn,hScroll);
			      end; {if}
			   end; {with}
      file_PageSetup:	DoPageSetup;
      file_Print:	DoPrint;
      file_Quit:	done := FileQuit;

      windows_Tile:	MenuTile;
      windows_Stack:	MenuStack;
      windows_Shell:	MenuShell;

      edit_Undo:	begin
			DoUndo;
			DrawScreen;
			end;
      edit_Cut:		begin
			CopySelection;
			DeleteSelection;
			DrawScreen;
			ShowCursor;
			end;
      edit_Clear:	begin
			DeleteSelection;
			DrawScreen;
			ShowCursor;
			end;
      edit_Copy:	CopySelection;
      edit_Paste:	begin
			DeleteSelection;
			DoPaste(true,nil,0);
			DrawScreen;
			end;
      edit_SelectAll:	SelectAll;

      find_Find:	DoFind;
      find_FindSame:	begin
			WaitCursor;
			Find(findPatt,isWholeWord,isCaseSensitive,
			   isFoldWhiteSpace,true);
			ResetCursor;
			end;
      find_DisplaySelection: FollowCursor;
      find_Replace:	DoReplace;
      find_ReplaceSame:	begin
			WaitCursor;
			DeleteSelection;
			DoPaste(false,pointer(ord4(@replacePatt)+1),
			   ord(replacePatt[0]));
			Find(findPatt,isWholeWord,isCaseSensitive,
			   isFoldWhiteSpace,true);
			ResetCursor;
			end;
      find_Goto:	DoGoto;

      extras_ShiftLeft:	ShiftLeft;
      extras_ShiftRight: ShiftRight;
      extras_DeleteToEndOfLine: DoDeleteToEol;
      extras_JoinLines:	DoJoinLines;
      extras_InsertLine: DoInsertLine;
      extras_DeleteLine: DoDeleteLine;
      extras_AutoIndent:
			with currentFile do
			  autoReturn := not autoReturn;
      extras_OverStrike:
			with currentFile do
			   insert := not insert;
      extras_ShowRuler:	DoShowRuler;
      extras_AutoSave:	autoSave := not autoSave;

      run_CompileToMemory: begin
			status := go;
			DoCompile(memory,7,7);
			end;
      run_CompileToDisk: begin
			status := go;
			DoCompile(disk,7,7);
			end;
      run_CheckForErrors: DoCompile(scan,1,7);
      run_GraphicsWindow: MenuGraphics;
      run_Compile:	DoCompile2;
      run_Link:		DoLink;
      run_Execute:	DoExecute;
      run_ExecuteOptions: DoExecuteOptions;

      debug_Step:	begin
			status := step;
			if executing then
			   done := true
			else
			   DoCompile(memory,7,8);
			end;
      debug_StepThru:	if executing then begin
			   stepOnReturn := true;
			   stepThru := true;
			   returnCount := 0;
			   status := go;
			   done := true;
			   end; {if}
      debug_Trace:	begin
			status := trace;
			if executing then
			   done := true
			else
			   DoCompile(memory,7,8);
			end;
      debug_Go:		begin
			status := go;
			if executing then
			   done := true
			else
			   DoCompile(memory,7,8);
			end;
      debug_GoToNextReturn:
			if executing then begin
			   stepOnReturn := true;
			   returnCount := 1;
			   status := go;
			   done := true;
			   end; {if}
      debug_Stop:	if executing then begin
                           qtDCB.pcount := 2;
			   qtDCB.pathName := nil;
			   qtDCB.flags := 0;
			   QuitGS(qtDCB);
			   end; {if}
      debug_Profile:	profile := not profile;
      debug_SetClearBreakPoint:
			if currentFile.newDebug then
			   DoSetClearMark(newBreakPoint)
                        else
			   DoSetClearMark(oldBreakPoint);
      debug_SetClearAutoGo:
			if currentFile.newDebug then
			   DoSetClearMark(newAutoGo)
                        else
			   DoSetClearMark(oldAutoGo);
      debug_Variables:	DoVariables;

      languages_Shell:	with currentFile do begin
			   language := -1;
			   changed := true;
			   changesSinceCompile := true;
			   end;

      otherwise:	if long(lastEvent.taskData).lsw > languages_Shell then begin
			   lp := languages;
			   while lp^.menuItem <> long(lastEvent.taskData).lsw do
			      lp := lp^.next;
			   currentFile.language := lp^.number;
			   currentFile.changed := true;
			   currentFile.changesSinceCompile := true;
			   ResetCursor;
			   if AlertWindow($0005, nil, base + alertID) = 0 then
			      with currentFile do begin
				 SetTabs(language, insert, autoReturn, ruler,
                                    newDebug);
				 if showRuler then begin
				    currentPtr^ := currentFile;
				    StartInfoDrawing(r,wPtr);
				    DrawRuler(r,ord4(@currentFile),wPtr);
				    EndInfoDrawing;
				    end; {if}
				 end; {with}
			   end {if}
			else
			   MenuSelectWindow(long(lastEvent.taskData).lsw);
   end; {case}
   CheckMenuItems;			{update menu status}
					{unhilite the menu}
   HiliteMenu(false,long(lastEvent.taskData).msw);
   end; {DoMenu}


begin {Events}
if FrontWindow <> nil then		{be sure we draw to the active window  }
   StartDrawing(FrontWindow);		{ unless we deliberately choose not to }
p.v := lastEvent.eventWhere.v;		{draw the proper cursor}
p.h := lastEvent.eventWhere.h;
GlobalToLocal(p);
isSysWindow := false;
if FrontWindow <> nil then begin
   isSysWindow := GetSysWFlag(FrontWindow);
   if (filePtr <> nil) or (FrontWindow = frWPtr) then
      with currentFile do
	 TrackCursor(p.v,p.h,width,maxHeight,false);
   end; {if}
if isSysWindow then begin
   if event = wInMenuBar then
      DoMenu
   else if event = wInSpecial then
      HiliteMenu(false,long(lastEvent.taskData).msw);
   end {else}
else case event of

   wInMenuBar,wInSpecial: DoMenu;

   wInGoAway: begin
      lastWasClick := false;
      if cursorVisible then Blink;
      CloseCurrentWindow(done,executing,7);
      end;

   wInControl:
      if FrontWindow = frWPtr then
         HandleReplaceEvent(lastEvent);

   wInZoom:
      with lastEvent, eventWhere do
	 if currentPtr <> nil then
	    if grafPortPtr(taskData) = currentFile.wPtr then
	       if TrackZoom(h,v,grafPortPtr(taskData)) then
		  DoZoom;

   wInContent,wInInfo:
      if frWPtr = grafPortPtr(lastEvent.taskData) then
         {do nothing}
      else if MyWindow(grafPortPtr(lastEvent.taskData)) then begin
	 if cursorVisible then Blink;	{mouse down in our window}
	 clickWhen := lastEvent.eventWhen;
	 Expand;
	 disableScreenUpdates := false;
	 DoContent;
	 if executing then begin
	    disableScreenUpdates := true;
	    if currentPtr <> nil then
	       currentPtr^ := currentFile
	    end; {if}
	 end; {if}

   autoKeyEvt,keyDownEvt: begin
      fw := FrontWindow;
      if fw <> nil then begin
	 if cursorVisible then Blink;
	 if (fw = currentFile.wPtr) and not executing then begin
	    lastWasClick := false;
	    DoKeyDown(lastEvent);
	    end; {if}
	 end; {if}
      end;

   activateEvt: begin
      if odd(lastEvent.eventModifiers) then begin
	 StartDrawing(grafPortPtr(lastEvent.eventMessage));
	 tbool := FindActiveFile(grafPortPtr(lastEvent.eventMessage));
	 CheckWindow(grafPortPtr(lastEvent.eventMessage));
	 end; {if}
      DrawControls(grafPortPtr(lastEvent.eventMessage));
      CheckMenuItems;
      end;

   otherwise: CheckMenuItems

   end; {case}
if not executing then begin
   elapsed := TickCount-lastHeartBeat;	{update tick count}
   if FrontWindow = currentFile.wPtr then
      if cursorVisible then begin
	 if elapsed > onTime then Blink;
	 end
      else begin
	 if elapsed > offTime then Blink;
	 end;
   if FrontWindow = nil then		{check menu status}
      SetMenuState(noWindow)
   else if isSysWindow then
      SetMenuState(sysWindow)
   else if SpecialWindow(FrontWindow) then
      SetMenuState(specWindow)
   else if currentFile.selection then
      SetMenuState(fullMenu)
   else
      SetMenuState(noSelection);
   end; {if}
end; {Events}


procedure InitORCA;

{ Do one-time initialization for this module			}


   procedure ReadCommandLine;

   { Read the command line and open any listed files		}

   type
      tokenType = gsosInString;		{token type}

   var
      cp: 0..255;			{character pointer}
      line: string[255];		{command line}
      token: tokenType;			{current token; null string if none left}


      procedure NextToken (var token: tokenType);

      { Get the next token from the command line		}
      {								}
      { Parameters:						}
      {    token - (output) token read; length is 0 if there	}
      {       are none left in the line				}

      begin {NextToken}
      while (cp <= length(line)) and (line[cp] in [' ', chr(tab)]) do
         cp := cp + 1;
      token.size := 0;
      while (cp <= length(line)) and (not (line[cp] in [' ', chr(tab)])) do
         begin
         token.size := token.size + 1;
         token.theString[token.size] := line[cp];
         cp := cp + 1;
         end; {while}
      end; {NextToken}


      procedure OpenFile (var token: tokenType);

      { Open a file						}
      {								}
      { Parameters:						}
      {    token - (input; var for efficiency) name of the file	}
      {		to open						}

      var
         inRec: initWildcardDCBGS;	{InitWildcard record}
         nxRec: nextWildcardDCBGS;	{NextWildcard record}
         name: gsosOutString;		{file name}

      begin {OpenFile}

      {set up for a wildcard search}
      inRec.pCount := 2;
      inRec.wFile := @token;
      inRec.flags := $8000;
      InitWildcardGS(inRec);

      {open all matching files}
      nxRec.pCount := 3;
      nxRec.pathName := @name;
      name.maxSize := sizeof(gsosOutString);
      repeat
         name.theString.size := 0;
         NextWildcardGS(nxRec);
         if name.theString.size <> 0 then
            if nxRec.fileType in [SRC, TXT] then
               OpenNewWindow(0, 25, 640, 175, @name.theString);
      until name.theString.size = 0;
      end; {OpenFile}


   begin {ReadCommandLine}
   CommandLine(line);
   cp := 1;
   NextToken(token);
   repeat
      NextToken(token);
      if token.size <> 0 then
         OpenFile(token);
   until token.size = 0;
   end; {ReadCommandLine}


begin {InitORCA}
currentPtr := nil;
WakeUp;
ReadCommandLine;
end; {InitORCA}

end.

{$append 'orca.asm'}
