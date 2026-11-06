Unicode true
!include "MUI2.nsh"
Name "Arara Music"
OutFile "Arara-Music-0.7.2-Windows-Instalador.exe"
InstallDir "$LOCALAPPDATA\Programs\Arara Music"
RequestExecutionLevel user
SetCompressor /SOLID lzma
!define MUI_ICON "AraraMusic\arara-music.ico"
!define MUI_UNICON "AraraMusic\arara-music.ico"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "AraraMusic\LICENSE.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\arara-music.exe"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "PortugueseBR"
VIProductVersion "0.7.2.0"
VIAddVersionKey /LANG=${LANG_PORTUGUESEBR} "ProductName" "Arara Music"
VIAddVersionKey /LANG=${LANG_PORTUGUESEBR} "FileVersion" "0.7.2"
VIAddVersionKey /LANG=${LANG_PORTUGUESEBR} "FileDescription" "Instalador do Arara Music"
VIAddVersionKey /LANG=${LANG_PORTUGUESEBR} "LegalCopyright" "GPL-3.0-or-later"
Section "Arara Music"
  SetOutPath "$INSTDIR"
  File /r "AraraMusic\*.*"
  WriteUninstaller "$INSTDIR\Desinstalar.exe"
  CreateDirectory "$SMPROGRAMS\Arara Music"
  CreateShortcut "$SMPROGRAMS\Arara Music\Arara Music.lnk" "$INSTDIR\arara-music.exe" "" "$INSTDIR\arara-music.ico"
  CreateShortcut "$DESKTOP\Arara Music.lnk" "$INSTDIR\arara-music.exe" "" "$INSTDIR\arara-music.ico"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AraraMusic" "DisplayName" "Arara Music"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AraraMusic" "DisplayVersion" "0.7.2"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AraraMusic" "DisplayIcon" "$INSTDIR\arara-music.ico"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AraraMusic" "UninstallString" "$INSTDIR\Desinstalar.exe"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AraraMusic" "NoModify" 1
SectionEnd
Section "Uninstall"
  RMDir /r "$INSTDIR"
  Delete "$DESKTOP\Arara Music.lnk"
  RMDir /r "$SMPROGRAMS\Arara Music"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AraraMusic"
SectionEnd
