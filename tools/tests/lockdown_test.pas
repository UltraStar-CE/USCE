program LockdownTest;
{$mode delphi}
uses Classes, SysUtils, ULibraryLockdown;

procedure Expect(Value: boolean; const Message: string);
begin
  if not Value then raise Exception.Create(Message);
end;

var Policy: TLibraryLockdown; LibrarySongs, Selected: TList;
    A, B, C: TObject;
begin
  Policy := TLibraryLockdown.Create;
  LibrarySongs := TList.Create;
  Selected := TList.Create;
  A := TObject.Create; B := TObject.Create; C := TObject.Create;
  try
    LibrarySongs.Add(A); LibrarySongs.Add(B); LibrarySongs.Add(C);
    Expect(not Policy.Activate(LibrarySongs, Selected, 'password'), 'Empty selection accepted');
    Selected.Add(B);
    Expect(not Policy.Activate(LibrarySongs, Selected, ''), 'Empty password accepted');
    Expect(Policy.Activate(LibrarySongs, Selected, 'Password'), 'Activation failed');
    Expect(Policy.Active and (LibrarySongs.Count = 1) and (LibrarySongs[0] = B), 'Selection not frozen');
    Expect(not Policy.CheckPassword('password'), 'Password comparison ignored case');
    Expect(not Policy.Unlock(LibrarySongs, 'wrong'), 'Wrong password unlocked');
    Expect(Policy.Active and (LibrarySongs.Count = 1), 'Failed unlock changed library');
    Expect(not Policy.Activate(LibrarySongs, Selected, 'replacement'), 'Nested activation replaced scope');
    Expect(Policy.Unlock(LibrarySongs, 'Password'), 'Correct password did not unlock');
    Expect(not Policy.Active and (LibrarySongs.Count = 3), 'Full library not restored');
    Expect((LibrarySongs[0] = A) and (LibrarySongs[1] = B) and (LibrarySongs[2] = C), 'Original references/order lost');
    Expect(not Policy.CheckPassword('Password'), 'Password remained active after unlock');
    Selected.Clear; Selected.Add(C);
    Expect(Policy.Activate(LibrarySongs, Selected, 'second'), 'Second session failed');
    Expect((LibrarySongs.Count = 1) and (LibrarySongs[0] = C), 'Second session reused old scope');
    Expect(Policy.Unlock(LibrarySongs, 'second'), 'Second session unlock failed');
  finally
    Policy.Free; Selected.Free; LibrarySongs.Free;
    A.Free; B.Free; C.Free;
  end;
  WriteLn('PASS: frozen selection, password gates, failed attempts and full-library restoration');
end.
