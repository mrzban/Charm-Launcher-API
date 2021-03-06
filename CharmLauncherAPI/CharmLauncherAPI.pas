unit CharmLauncherAPI;

interface


uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Forms, Vcl.Dialogs, DBXJSON, ShellApi;


type
  MEMORYSTATUSEX = record
    dwLength: DWORD;
    dwMemoryLoad: DWORD;
    ullTotalPhys: Int64;
    ullAvailPhys: Int64;
    ullTotalPageFile: Int64;
    ullAvailPageFile: Int64;
    ullTotalVirtual: Int64;
    ullAvailVirtual: Int64;
    ullAvailExtendedVirtual: Int64;
  end;

  FJSONObject = TJSONObject;

  TAuthInfo = record
    Name: string[255];
    Password: string[255];
    Agent: string[255];
  end;

  TLaunchInfo = record
    JavaPath: string[255];
    GarbageCollectorEnabled: Boolean;
    MaxHeapSizeGb: string[2];
    Version: string[100];
    GameLibs: string;
    GameMainClass: string[100];
    auth_player_name: string[255];
    auth_uuid: string[255];
    auth_access_token: string[255];
    twitch_access_token: string[255];
    assets_index_name:  string[20];
    minecraft_arguments: string[255];

  end;


  TYggUserAuthentication = class(TObject)
  private
    Fauth_token: string;
    const BASE_URL           = 'https://authserver.mojang.com/';
    const ROUTE_AUTHENTICATE = 'https://authserver.mojang.com/authenticate';
    const ROUTE_REFRESH      = 'https://authserver.mojang.com/refresh';
    const ROUTE_VALIDATE     = 'https://authserver.mojang.com/validate';
    const ROUTE_INVALIDATE   = 'https://authserver.mojang.com/invalidate';
    const ROUTE_SIGNOUT      = 'https://authserver.mojang.com/signout';
  public
    constructor Create(const AuthInfo: TAuthInfo);
    property auth_token: string read Fauth_token;
  end;


  TLauncher = class(TObject)
    Logging: Boolean;
  private
    FGameDirectory: string;
    FLog: TStringList;
    function GetVersions: TStringList;
    Function DetectRam : integer;
    function ReplaceStr(Str, X, Y: string): string;
    procedure AddLog(text: string);
    function PrepareArgs(minecraft_arguments: string; LaunchInfo: TLaunchInfo): string;
  public
    constructor Create(const GameDirectory: string);
    function JsonParse(RawJsonFile: string): FJSONObject;
    function JsonExtractLibs(SourceObject: FJSONObject): string;
    function JsonExtractMainClass(SourceObject: FJSONObject): string;
    function JsonExtractAssetIndex(SourceObject: FJSONObject): string;
    function JsonExtractMinecraftArguments(SourceObject: FJSONObject): string;
    function LaunchGame(LaunchInfo: TLaunchInfo): integer;
    property GameDirectory: string read FGameDirectory;
    property AvailableRAM: integer read DetectRAM;
    function FindJavaPath: String;
    property Log: TStringList read FLog;
  published
    property Versions: TStringList read GetVersions;
  end;


implementation



{ TLauncher }

constructor TLauncher.Create(const GameDirectory: string);
begin

  FGameDirectory:=GameDirectory;
  SetCurrentDir(GameDirectory);
  FLog:=TstringList.Create;
  AddLog('Launcher started');
end;


procedure TLauncher.AddLog(text: string);
begin
  Flog.Add(timetostr(now) + ' ' + text);
end;


function TLauncher.LaunchGame(LaunchInfo: TLaunchInfo): integer;
var
  LaunchStr: String;
  GameJar: String;
  GameArgs: String;
begin
  AddLog('Launching game...');

  LaunchStr:='';
  if LaunchInfo.Version = ''then
    exit;
  if LaunchInfo.MaxHeapSizeGb = '' then
    exit;
  if LaunchInfo.GameMainClass = '' then
    exit;
  if LaunchInfo.minecraft_arguments = '' then
    exit;

   GameJar:='versions\' + LaunchInfo.Version + '\' + LaunchInfo.Version + '.jar';
   GameArgs:=PrepareArgs(LaunchInfo.minecraft_arguments, LaunchInfo);

  if (LaunchInfo.GarbageCollectorEnabled = True) then
    LaunchStr:=LaunchStr + '-Xincgc ';
  LaunchStr:=LaunchStr + '-Xmx' + LaunchInfo.MaxHeapSizeGb + 'g ';
  LaunchStr:=LaunchStr + '-Djava.library.path=versions\' + LaunchInfo.Version +'\natives ';
  LaunchStr:=LaunchStr + '-cp ' + LaunchInfo.GameLibs + GameJar + ' ';
  LaunchStr:=LaunchStr + LaunchInfo.GameMainClass + ' ';
  LaunchStr:=LaunchStr + GameArgs;

  AddLog('Launch command: ' + LaunchStr);

    ShellExecute(Application.Handle,
               'Open',
               Pchar('C:\Users\home\Desktop\Java64\bin\java.exe'),
               PChar(LaunchStr),
               nil,
               SW_SHOW );


end;



function TLauncher.GetVersions: TStringList;
  var
  searchResult : TSearchRec;
  i : integer;
begin
  Result:=TStringList.Create;

  if (FGameDirectory = '') then
    raise Exception.Create('Wrong Game Directory');

  if FGameDirectory[length(FGameDirectory)] = '\' then
    FGameDirectory:=Copy(FGameDirectory, 1, length(FGameDirectory)-1);

  if FindFirst(FGameDirectory + '\versions\' + '*', faDirectory, searchResult) = 0 then
  begin
    repeat
      if (searchResult.attr and faDirectory) = faDirectory
      then Result.add(searchResult.Name);
    until FindNext(searchResult) <> 0;
    FindClose(searchResult);

    //Clearing Results
    Result.Delete(0);
    Result.Delete(0);

    if Result.Count > 0 then
    begin
      for i := 0 to Result.Count-1 do
      begin
        if not FileExists(FGameDirectory + '\versions\' + Result[i] + '\' + Result[i] + '.json') then
          Result.Delete(i);
       end;
    end else
      raise Exception.Create('No versions installed!');
  end;

end;


function TLauncher.DetectRam : integer;
var
  MemoryInfo : _MEMORYSTATUSEX;
  TotalRAM : integer;
begin
  MemoryInfo.dwLength := SizeOf(MEMORYSTATUSEX) ;
  GlobalMemoryStatusEx(MemoryInfo);
  TotalRAM := trunc (MemoryInfo.ullTotalPhys div 1024 / 1024);
  Result := TotalRAM;
end;


function TLauncher.JsonParse(RawJsonFile: String): FJSONObject;
Var
  RawJSON: TStringList;
  ParsedObject: FJSONObject;
begin
  if not FileExists(RawJsonFile) then
    raise Exception.Create('JSON file does not exist');

  RawJSON:= TStringList.Create;
try
  RawJson.LoadFromFile(RawJsonFile);
  ParsedObject:=FJSONObject.Create;
  ParsedObject:=TJSONObject.ParseJSONValue( RawJSON.Text) as TJSONObject;
  if Assigned(ParsedObject) then
    Result:=ParsedObject
  else
    raise Exception.Create('JSON file corrupted');
finally
  RawJSON.Free;
end;

end;


function TLauncher.JsonExtractLibs(SourceObject: FJSONObject): string;
var
  ParsedLibraries: TStringList;
  JsonArray: TJSONArray;
  i, h: integer;
  current_str : string;
  List: TStrings;
  list_item: string;
begin
  ParsedLibraries:=TStringList.create;
  JsonArray:=TJSONArray.Create;
  JsonArray:=SourceObject.Get('libraries').JsonValue as TJsonArray;
  for I := 0 to JsonArray.Size-1 do begin
     ParsedLibraries.Add((JsonArray.Get(i) as TJSONObject).Get('name').JsonValue.Value);
  end;

  for i := 0 to ParsedLibraries.Count-1 do
  begin

    List := TStringList.Create;
    try
      ExtractStrings([':'], [], PChar(ParsedLibraries.Strings[i]), List);


      list_item:=List[0];
      for  h := 0 to Length(list_item)-1 do
      begin

        if List_item[h] = '.' then
            List_item[h] := '\' ;
      end;
      List[0]:=list_item;

      current_str:='libraries\' + List[0] +    '\' + List[1] + '\' + List[2] + '\' + List[1] + '-' + List[2] + '.jar;';
      ParsedLibraries.Strings[i]:=current_str;

    finally
      List.Free;
    end;


  end;


  Result:='';
  for i := 0 to ParsedLibraries.Count-1 do
  begin
    Result:=Result + ParsedLibraries.Strings[i];
  end;

end;

function TLauncher.JsonExtractMainClass(SourceObject: FJSONObject): string;
var
  Enum: TStringList;
  i: integer;
begin
  Result:='';
  if SourceObject.Size < 1 then
    exit;

  Enum:=TstringList.Create;
  for i := 0 to SourceObject.Size-1 do
    Enum.Add((SourceObject.Get(i)).JsonString.Value);

  for i := 0 to Enum.Count-1 do
  begin
    if Enum.Strings[i]='mainClass' then
      Result:=SourceObject.Get('mainClass').JsonValue.Value
  end;

  Enum.Free;
end;


function TLauncher.JsonExtractAssetIndex(SourceObject: FJSONObject): string;
var
  Enum: TStringList;
  i: integer;
begin
  Result:='';
  if SourceObject.Size < 1 then
    exit;

  Enum:=TstringList.Create;
  for i := 0 to SourceObject.Size-1 do
    Enum.Add((SourceObject.Get(i)).JsonString.Value);

  for i := 0 to Enum.Count-1 do
  begin
    if Enum.Strings[i]='assets' then
      Result:=SourceObject.Get('assets').JsonValue.Value
  end;

  Enum.Free;
end;

function TLauncher.JsonExtractMinecraftArguments(SourceObject: FJSONObject): string;
var
  Enum: TStringList;
  i: integer;
begin
  Result:='';
  if SourceObject.Size < 1 then
    exit;

  Enum:=TstringList.Create;
  for i := 0 to SourceObject.Size-1 do
    Enum.Add((SourceObject.Get(i)).JsonString.Value);

  for i := 0 to Enum.Count-1 do
  begin
    if Enum.Strings[i]='minecraftArguments' then
      Result:=SourceObject.Get('minecraftArguments').JsonValue.Value
  end;

  Enum.Free;
end;

function TLauncher.FindJavaPath: String;
var
  buff: array[0..255] of char;
begin
  ExpandEnvironmentStrings(PChar('%systemdrive%'),buff,SizeOf(buff));
  if FileExists(buff + '\Program Files\Java\bin\javaw.exe') then
    Result:=buff + '\Program Files\Java\';

 if FileExists(buff + '\Program Files(x86)\Java\bin\javaw.exe') then
   Result:=buff + '\Program Files(x86)\Java\';

  if FileExists(buff + '\Program Files\Java\jre7\bin\javaw.exe') then
    Result:=buff + '\Program Files\Java\jre7\';

  if FileExists(buff + '\Program Files\Java\jre6\bin\javaw.exe') then
    Result:=buff + '\Program Files\Java\jre6\';

  if FileExists(buff + '\Program Files(x86)\Java\jre7\bin\javaw.exe') then
    Result:=buff + '\Program Files(x86)\Java\jre7\';

  if FileExists(buff + '\Program Files(x86)\Java\jre6\bin\javaw.exe') then
    Result:=buff + '\Program Files(x86)\Java\jre6\';
end;


function TLauncher.ReplaceStr(Str, X, Y: string): string;
var
  buf1, buf2, buffer: string;
  i: Integer;

begin
  buf1 := '';
  buf2 := Str;
  Buffer := Str;

  while Pos(X, buf2) > 0 do
  begin
    buf2 := Copy(buf2, Pos(X, buf2), (Length(buf2) - Pos(X, buf2)) + 1);
    buf1 := Copy(Buffer, 1, Length(Buffer) - Length(buf2)) + Y;
    Delete(buf2, Pos(X, buf2), Length(X));
    Buffer := buf1 + buf2;
  end;

  ReplaceStr := Buffer;
end;


function TLauncher.PrepareArgs(minecraft_arguments: string; LaunchInfo: TLaunchInfo): string;
begin
  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${auth_session}', LaunchInfo.auth_uuid) ;

  //modern 1.6.1+
  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${auth_player_name}', LaunchInfo.auth_player_name) ;
  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${version_name}', LaunchInfo.Version) ;
  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${game_directory}', '.\') ;
  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${game_assets}', '.\assets\virtual\legacy') ;

  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${auth_uuid}', LaunchInfo.auth_uuid) ;
  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${auth_access_token}', LaunchInfo.auth_access_token) ;

  //1.7.2+
  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${user_properties}', '{"twitch_access_token":["' + LaunchInfo.twitch_access_token + '"]}') ;
  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${user_type}', 'legacy') ;
  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${assets_root}', '.\assets');
  minecraft_arguments:=ReplaceStr(minecraft_arguments, '${assets_index_name}', LaunchInfo.assets_index_name) ;

  Result:=minecraft_arguments;


end;


{ TUserAuthentication}

constructor TYggUserAuthentication.Create(const AuthInfo: TAuthInfo);
begin

end;

end.
