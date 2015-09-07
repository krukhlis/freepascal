
function LOBYTE(w: Word): Byte;
begin
  LOBYTE := Byte(w);
end;

function HIBYTE(w: Word): Byte;
begin
  HIBYTE := Byte(w shr 8);
end;

function LOWORD(l: LongInt): Word;
begin
  LOWORD := Word(l);
end;

function HIWORD(l: LongInt): Word;
begin
  HIWORD := Word(l shr 16);
end;

function MAKELONG(low, high: Word): LONG;
begin
  MAKELONG := low or (LongInt(high) shl 16);
end;

function MAKELPARAM(low, high: Word): LPARAM;
begin
  MAKELPARAM := MAKELONG(low, high);
end;

function MAKELRESULT(low, high: Word): LRESULT;
begin
  MAKELRESULT := MAKELONG(low, high);
end;

function MAKELP(sel, off: Word): FarPointer;
begin
  MAKELP := Ptr(sel, off);
end;

function SELECTOROF(lp: FarPointer): Word;
begin
  SELECTOROF:=HIWORD(LongInt(lp));
end;

function OFFSETOF(lp: FarPointer): Word;
begin
  OFFSETOF:=LOWORD(LongInt(lp));
end;

function GlobalDiscard(h: HGLOBAL): HGLOBAL;
begin
  GlobalDiscard := GlobalReAlloc(h, 0, GMEM_MOVEABLE);
end;

function LockData(dummy: SmallInt): HGLOBAL;
begin
  LockData := LockSegment(UINT(-1));
end;

procedure UnlockData(dummy: SmallInt);
begin
  UnlockSegment(UINT(-1));
end;

function LocalDiscard(h: HLOCAL): HLOCAL;
begin
  LocalDiscard := LocalReAlloc(h, 0, LMEM_MOVEABLE);
end;