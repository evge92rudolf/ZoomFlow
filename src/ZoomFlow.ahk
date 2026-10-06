#Requires AutoHotkey v2.0
#SingleInstance Force
; ZoomFlow 1.7.2 — Windows / AutoHotkey v2
; Quit earlier zoom scripts before launching this file.
; Default: Ctrl + MMB + move mouse to zoom. Ctrl + Alt + Z: settings.
; Ctrl + Alt + Esc: exit and release cursor.

InstallKeybdHook()
InstallMouseHook()
SetMouseDelay -1

ConfigDir := A_AppData "\ZoomFlow"
ConfigPath := ConfigDir "\settings.ini"
; Preserve the settings from Zoom Drag on the first launch after renaming.
if !FileExist(ConfigPath) && FileExist(A_AppData "\ZoomDrag\settings.ini") {
    try {
        DirCreate ConfigDir
        FileCopy A_AppData "\ZoomDrag\settings.ini", ConfigPath, false
    }
}
Cfg := Map(
    "Smoothing", ReadSetting("Smoothing", 35, 0, 150),
    "Inertia", ReadSetting("Inertia", 100, 0, 300),
    "Speed", ReadSetting("Speed", 100, 25, 300),
    "Acceleration", ReadSetting("Acceleration", 0, 0, 100),
    "MaxGain", ReadSetting("MaxGain", 20, 10, 40),
    "Interval", ReadSetting("Interval", 10, 10, 30),
    "Reverse", ReadSetting("Reverse", 0, 0, 1),
    "Fine", ReadSetting("Fine", 0, 0, 1),
    "Illustrator", ReadSetting("Illustrator", 1, 1, 2),
    "Axis", ReadSetting("Axis", 1, 1, 2),
    "Mod1", ReadSetting("Mod1", 2, 1, 5),
    "Mod2", ReadSetting("Mod2", 1, 1, 5),
    "Key", ReadKeySetting()
)
TestSession := false
TestScale := 1.0
TestBitmap := 0
TestPercentValue := "100%"
PauseInk := "7E420D"
SessionCfg := Cfg.Clone()
Enabled := true
ZoomActive := false
CursorLocked := false
RawMotion := 0
Accum := 0.0
FilteredRate := 0.0
LastMotion := 0
LastTick := 0
TargetWindow := 0
Captured := false
BoundDown := ""
BoundUp := ""
ModNames := ["", "Ctrl", "Alt", "Shift", "Win"]
ModSymbols := ["", "^", "!", "+", "#"]
TriggerKeys := ["MButton", "XButton1", "XButton2", "RButton", "LButton", "Space", "F8", "F9", "F10", "Custom"]
C := Map()
Pages := Map(1, [], 2, [], 3, [], 4, [])
PageIndex := 0
CurrentPage := 1
ButtonKinds := Map()
TextLayouts := Map()
OnMessage 0x002B, DrawButton

SettingsUI := Gui("+DPIScale", "ZoomFlow — настройки")
BuildUI()
try {
    ValidateGesture(Cfg)
    BindGesture(Cfg)
} catch {
    Cfg["Mod1"] := 2
    Cfg["Mod2"] := 1
    Cfg["Key"] := "MButton"
    BindGesture(Cfg)
    C["Mod1"].Choose(2)
    C["Mod2"].Choose(1)
    C["Trigger"].Choose(1)
}
RefreshGesture()

OnExit Cleanup
OnError HandleError
OnMessage 0x00FF, ReadMouseInput
device := Buffer(8 + A_PtrSize, 0)
NumPut "UShort", 1, device, 0
NumPut "UShort", 2, device, 2
NumPut "UInt", 0x100, device, 4
NumPut "Ptr", A_ScriptHwnd, device, 8
if !DllCall("RegisterRawInputDevices", "Ptr", device.Ptr,
    "UInt", 1, "UInt", device.Size, "Int")
{
    MsgBox "Не удалось подключить мышь через Raw Input. Код: " A_LastError
    ExitApp()
}

A_TrayMenu.Delete()
A_TrayMenu.Add("Настройки", ShowSettings)
A_TrayMenu.Default := "Настройки"
A_TrayMenu.ClickCount := 2
A_TrayMenu.Add("Пауза / продолжить", ToggleEnabled)
A_TrayMenu.Add()
A_TrayMenu.Add("Выход", Quit)
A_IconTip := "ZoomFlow — настройки сочетания в меню"
if !(A_Args.Length > 0 && A_Args[1] = "--autostart")
    ShowSettings()

^!z::ShowSettings()
^!Esc::Quit()

ReadKeySetting()
{
    global ConfigPath
    try {
        return IniRead(ConfigPath, "Zoom", "Key", "MButton")
    }
    return "MButton"
}

ReadSetting(key, fallback, low, high)
{
    global ConfigPath
    try {
        value := IniRead(ConfigPath, "Zoom", key, fallback)
        if IsNumber(value)
            return Round(Max(low, Min(high, value + 0)))
    }
    return fallback
}

BuildUI()
{
    global SettingsUI, C, Cfg, TriggerKeys, PageIndex
    SettingsUI.BackColor := "F7F6FA"
    SettingsUI.SetFont("s10 c262234", "Segoe UI")
    SettingsUI.AddPicture("x0 y0 w800 h700", BackgroundFile())
    TextAt("ZoomFlow", 64, 26, 126, 32, 16, "262234", true)
    TextAt("by Design Flow", 22, 75, 166, 22, 9, "82798E")
    names := ["Зум", "Управление", "Плавность", "Программа"]
    for i, name in names {
        C["Nav" i] := ButtonAt(name, 20, 130 + (i-1)*56, 160, 44, "nav" i)
        C["Nav" i].OnEvent("Click", SwitchPage.Bind(i))
    }
    C["PauseCard"] := SettingsUI.AddPicture("x20 y535 w160 h153", PauseCardFile())
    C["PauseCard"].Visible := false
    C["State"] := SettingsUI.AddText("x36 y553 w132 h26 +0xD", "")
    C["State"].SetFont("s11 Bold", "Segoe UI")
    TextAt("Управляй масштабом`nдвижением мыши.", 36, 592, 132, 38, 9, "7B708E")
    C["Pause"] := ButtonAt("Пауза", 32, 634, 136, 40, "status")
    C["Pause"].OnEvent("Click", ToggleEnabled)
    TextAt("Масштаб под твоим", 248, 34, 430, 38, 22, "FFFFFF", false)
    TextAt("контролем.", 248, 72, 430, 36, 22, "D7CAFF", false)
    TextAt("Меньше движений. Больше потока.", 248, 119, 425, 20, 10, "DDD3F5")

    PageIndex := 1
    TextAt("Настрой свой темп", 248, 192, 500, 30, 18, "262234", true)
    TextAt("Выбери пресет или отрегулируй зум вручную.", 248, 230, 500, 22, 10, "82798E")
    for i, label in ["Точный", "Обычный", "Быстрый"] {
        speeds := [60, 100, 160]
        speed := speeds[i]
        ButtonAt(label, 248+(i-1)*172, 268, 156, 40).OnEvent("Click", Preset.Bind(speed))
    }
    C["SpeedLabel"] := TextAt("",248,324,500,24,11,"262234",true)
    C["Speed"] := ControlAt("Slider","x248 y354 w500 h28 Range25-300 ToolTip NoTicks",Cfg["Speed"])
    C["AccelerationLabel"] := TextAt("",248,390,500,24,11,"262234",true)
    C["Acceleration"] := ControlAt("Slider","x248 y418 w500 h28 Range0-100 ToolTip NoTicks",Cfg["Acceleration"])
    C["GainLabel"] := TextAt("",248,450,280,24,10,"82798E")
    C["MaxGain"] := ControlAt("Slider","x548 y448 w200 h28 Range10-40 NoTicks",Cfg["MaxGain"])
    C["GainHint"] := TextAt("",248,480,500,36,9,"82798E")
    TextAt("Интервал обновления зума · мс",248,520,320,24,10,"82798E")
    C["Interval"] := ControlAt("DropDownList","x584 y516 w164",["10","15","20","30"])
    chosen := 1
    for i,n in [10,15,20,30] {
        if n = Cfg["Interval"]
            chosen := i
    }
    C["Interval"].Choose(chosen)
    TextAt("Задержка между обновлениями зума.`n10 мс — обновления чаще; 30 мс — реже. Обычно оставь 10 мс.",248,548,500,30,9,"82798E")

    PageIndex := 2
    TextAt("Твой привычный жест",248,192,500,30,18,"262234",true)
    TextAt("Сначала модификаторы, затем удерживаемая кнопка.",248,230,500,22,10,"82798E")
    TextAt("Движение",248,279,185,24)
    C["Axis"] := ControlAt("DropDownList","x452 y273 w296",["Вверх / вниз","Влево / вправо"])
    C["Axis"].Choose(Cfg["Axis"])
    TextAt("Основная клавиша",248,321,192,24)
    C["Mod1"] := ControlAt("DropDownList","x452 y315 w296",["Без модификатора","Ctrl","Alt","Shift","Win"])
    C["Mod1"].Choose(Cfg["Mod1"])
    TextAt("Дополнительная",248,363,192,24)
    C["Mod2"] := ControlAt("DropDownList","x452 y357 w296",["Не добавлять","Ctrl","Alt","Shift","Win"])
    C["Mod2"].Choose(Cfg["Mod2"])
    TextAt("Удерживаемая кнопка",248,405,195,24)
    C["Trigger"] := ControlAt("DropDownList","x452 y399 w296",["Средняя кнопка мыши","Боковая кнопка X1","Боковая кнопка X2","Правая кнопка мыши","Левая кнопка мыши","Пробел","F8","F9","F10","Другая клавиша…"])
    selected := 10
    for i,key in TriggerKeys {
        if key = Cfg["Key"]
            selected := i
    }
    C["Trigger"].Choose(selected)
    TextAt("Другая: Q, F6, Tab…",248,447,190,24,10,"82798E")
    C["Custom"] := ControlAt("Edit","x452 y441 w296 h28",selected = 10 ? Cfg["Key"] : "")
    C["Reverse"] := ControlAt("Checkbox","x248 y484 w500 h26","Инвертировать направление")
    C["Reverse"].Value := Cfg["Reverse"]
    C["Preview"] := TextAt("",248,523,500,45,9,"6344D7")
    for key in ["Axis","Mod1","Mod2","Trigger","Custom"]
        C[key].OnEvent("Change",RefreshGesture)

    PageIndex := 3
    TextAt("Движение без спешки",248,192,500,30,18,"262234",true)
    TextAt("Подбери отклик и мягкое затухание зума.",248,230,500,22,10,"82798E")
    C["SmoothingLabel"] := TextAt("",248,273,500,24,11,"262234",true)
    C["Smoothing"] := ControlAt("Slider","x248 y303 w500 h28 Range0-150 NoTicks ToolTip",Cfg["Smoothing"])
    TextAt("Выше — мягче отклик. 0 — без сглаживания.",248,341,500,22,9,"82798E")
    C["InertiaLabel"] := TextAt("",248,388,500,24,11,"262234",true)
    C["Inertia"] := ControlAt("Slider","x248 y418 w500 h28 Range0-300 NoTicks ToolTip",Cfg["Inertia"])
    TextAt("0 — без инерции.`nОтпусти сочетание, чтобы остановить зум.",248,452,500,36,9,"82798E")
    C["Fine"] := ControlAt("Checkbox","x248 y500 w500 h26","Дробное колесо · экспериментально")
    C["Fine"].Value := Cfg["Fine"]
    TextAt("Поддержка зависит от приложения. Только с Ctrl.`nЕсли появились рывки — отключи дробное колесо.",248,528,500,40,9,"82798E")

    PageIndex := 4
    TextAt("Всегда под рукой",248,192,500,30,18,"262234",true)
    TextAt("Запуск, совместимость и быстрый доступ.",248,230,500,22,10,"82798E")
    C["Autostart"] := ControlAt("Checkbox","x248 y275 w500 h28","Запускать вместе с Windows")
    C["Autostart"].Value := !!(FileExist(StartupLink()) || FileExist(A_Startup "\Zoom Drag.lnk"))
    C["Autostart"].OnEvent("Click",ChangeAutostart)
    TextAt("Применяется сразу. При входе окно остаётся скрытым.",248,312,500,22,9,"82798E")
    C["StartupStatus"] := TextAt("",248,350,500,68,9,"6344D7")
    TextAt("Adobe Illustrator",248,433,500,24,11,"262234",true)
    C["Illustrator"] := ControlAt("DropDownList","x248 y465 w500",["Не перехватывать (рекомендуется)","Ctrl + колесо, как в остальных программах"])
    C["Illustrator"].Choose(Cfg["Illustrator"])
    TextAt("Настройки  ·  Ctrl + Alt + Z`nВыход  ·  Ctrl + Alt + Esc",248,521,500,42,10,"82798E")
    RefreshStartupStatus()

    PageIndex := 0
    C["TestPanel"] := SettingsUI.AddText("x800 y172 w296 h408 +0xD", "")
    TextAt("Проверить зум",824,192,248,30,17,"262234",true)
    C["TestHint"] := TextAt("",824,235,248,66,9,"82798E")
    C["Canvas"] := SettingsUI.AddText("x824 y312 w248 h184 +0xD", "")
    C["TestPercent"] := SettingsUI.AddText("x824 y512 w248 h30 +0xD", "")
    C["TestPercent"].SetFont("s17 c6344D7 Bold", "Segoe UI")
    TextAt("Сетка и фигура — тестовый холст.",824,548,248,20,9,"82798E")
    ButtonAt("Сбросить масштаб",800,600,296,44).OnEvent("Click",ResetTest)
    TextAt("Отклик в других приложениях`nможет отличаться от этого теста.",804,658,288,36,9,"82798E")
    TextAt("Попробуй в движении",804,28,292,30,17,"262234",true)
    TextAt("Наведи мышь на холст и зажми сочетание.`nСкорость и плавность меняются сразу.`nНовые клавиши примени кнопкой слева.",804,68,288,92,9,"82798E")
    ButtonAt("Применить и сохранить",220,600,252,44,"primary").OnEvent("Click",SaveSettings)
    ButtonAt("Скрыть",484,600,136,44).OnEvent("Click",HideSettings)
    ButtonAt("Помощь",632,600,144,44).OnEvent("Click",ShowHelp)
    C["Notice"] := TextAt("Выбери настройки и нажми «Применить и сохранить».",224,658,548,36,9,"82798E")
    for key in ["Speed","Acceleration","MaxGain","Smoothing","Inertia"]
        C[key].OnEvent("Change",RefreshLabels)
    SettingsUI.OnEvent("Close",HideSettings)
    SettingsUI.OnEvent("Escape",HideSettings)
    RefreshLabels()
    RefreshGesture()
    SwitchPage(1)
    UpdateTestHint()
    RenderTest()
    SetTimer UpdateTestHint, 120
    SetTimer FitInterfaceText, 250
}

ControlAt(type, options, value)
{
    global SettingsUI, Pages, PageIndex
    ctrl := SettingsUI.Add(type, options, value)
    ; Sliders use native Windows painting, including focus and DPI scaling.
    if type = "Edit" || type = "DropDownList"
        RoundField(ctrl)
    if PageIndex
        Pages[PageIndex].Push(ctrl)
    return ctrl
}

RoundField(ctrl, cornerDiameter:=12)
{
    rect := Buffer(16, 0)
    DllCall("GetWindowRect", "Ptr", ctrl.Hwnd, "Ptr", rect)
    width := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
    height := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
    radius := Round(cornerDiameter * A_ScreenDPI / 96)
    region := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", width+1,
        "Int", height+1, "Int", radius, "Int", radius, "Ptr")
    if region && !DllCall("SetWindowRgn", "Ptr", ctrl.Hwnd, "Ptr", region, "Int", true)
        DllCall("DeleteObject", "Ptr", region)
}

TextAt(text,x,y,w,h,size:=10,color:="262234",bold:=false)
{
    ctrl := ControlAt("Text", "x" x " y" y " w" w " h" h " BackgroundTrans", text)
    ctrl.SetFont("s" size " c" color (bold ? " Bold" : " Norm"),"Segoe UI")
    global TextLayouts
    TextLayouts[ctrl.Hwnd] := {Control:ctrl, BaseSize:size, CurrentSize:size, Cache:""}
    FitLabel(TextLayouts[ctrl.Hwnd])
    return ctrl
}

ButtonAt(text,x,y,w,h,kind:="secondary")
{
    global ButtonKinds, PageIndex
    ctrl := ControlAt("Button","x" x " y" y " w" w " h" h,text)
    ctrl.SetFont("s10" (kind = "primary" ? " Bold" : " Norm"), "Segoe UI")
    ButtonKinds[ctrl.Hwnd] := {Kind:kind, OnCard:PageIndex > 0}
    DllCall("UxTheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "", "Str", "")
    ; BM_SETSTYLE replaces the button type instead of mixing style bits.
    DllCall("SendMessageW", "Ptr", ctrl.Hwnd, "UInt", 0xF4, "UPtr", 0xB, "Ptr", true, "Ptr")
    return ctrl
}

SwitchPage(index,*)
{
    global Pages, CurrentPage, C, SettingsUI
    CurrentPage := index
    for number, controls in Pages {
        for ctrl in controls
            ctrl.Visible := number = index
    }
    Loop 4
        DllCall("InvalidateRect","Ptr",C["Nav" A_Index].Hwnd,"Ptr",0,"Int",true)
    titles := ["Зум", "Управление", "Плавность", "Программа"]
    SettingsUI.Title := "ZoomFlow — " . titles[index]
    DllCall("RedrawWindow","Ptr",SettingsUI.Hwnd,"Ptr",0,"Ptr",0,"UInt",0x185)
}

DrawButton(wParam,lParam,*)
{
    global ButtonKinds, CurrentPage, Enabled, C, TestBitmap, TestPercentValue, PauseInk
    ; DRAWITEMSTRUCT layout differs between 32-bit and 64-bit Windows.
    hwndOffset := A_PtrSize = 8 ? 24 : 20
    hwnd := NumGet(lParam,hwndOffset,"Ptr")
    if C.Has("TestPanel") && hwnd = C["TestPanel"].Hwnd {
        target := NumGet(lParam,hwndOffset+A_PtrSize,"Ptr")
        offset := hwndOffset+2*A_PtrSize
        width := NumGet(lParam,offset+8,"Int")-NumGet(lParam,offset,"Int")
        height := NumGet(lParam,offset+12,"Int")-NumGet(lParam,offset+4,"Int")
        background := DllCall("CreateSolidBrush","UInt",ColorRef("F7F6FA"),"Ptr")
        DllCall("FillRect","Ptr",target,"Ptr",lParam+offset,"Ptr",background)
        DllCall("DeleteObject","Ptr",background)
        SmoothRound(target,0,0,width,height,24*A_ScreenDPI/96,"FFFFFF")
        return true
    }
    if C.Has("Canvas") && hwnd = C["Canvas"].Hwnd {
        if TestBitmap {
            target := NumGet(lParam,hwndOffset+A_PtrSize,"Ptr")
            offset := hwndOffset+2*A_PtrSize
            width := NumGet(lParam,offset+8,"Int")-NumGet(lParam,offset,"Int")
            height := NumGet(lParam,offset+12,"Int")-NumGet(lParam,offset+4,"Int")
            memory := DllCall("CreateCompatibleDC","Ptr",target,"Ptr")
            previous := DllCall("SelectObject","Ptr",memory,"Ptr",TestBitmap,"Ptr")
            DllCall("BitBlt","Ptr",target,"Int",0,"Int",0,"Int",width,"Int",height,
                "Ptr",memory,"Int",0,"Int",0,"UInt",0xCC0020)
            DllCall("SelectObject","Ptr",memory,"Ptr",previous)
            DllCall("DeleteDC","Ptr",memory)
        }
        return true
    }
    if (C.Has("TestPercent") && hwnd = C["TestPercent"].Hwnd) || (C.Has("State") && hwnd = C["State"].Hwnd) {
        isState := C.Has("State") && hwnd = C["State"].Hwnd
        target := NumGet(lParam,hwndOffset+A_PtrSize,"Ptr")
        offset := hwndOffset+2*A_PtrSize
        width := NumGet(lParam,offset+8,"Int")-NumGet(lParam,offset,"Int")
        height := NumGet(lParam,offset+12,"Int")-NumGet(lParam,offset+4,"Int")
        memory := DllCall("CreateCompatibleDC","Ptr",target,"Ptr")
        frame := DllCall("CreateCompatibleBitmap","Ptr",target,"Int",width,"Int",height,"Ptr")
        previous := DllCall("SelectObject","Ptr",memory,"Ptr",frame,"Ptr")
        bounds := Buffer(16,0)
        NumPut("Int",width,"Int",height,bounds,8)
        brush := DllCall("CreateSolidBrush","UInt",ColorRef(isState ? (Enabled ? "F4F0FF" : "FFF4DB") : "FFFFFF"),"Ptr")
        DllCall("FillRect","Ptr",memory,"Ptr",bounds,"Ptr",brush)
        DllCall("DeleteObject","Ptr",brush)
        font := SendMessage(0x31,0,0,hwnd)
        oldFont := DllCall("SelectObject","Ptr",memory,"Ptr",font,"Ptr")
        DllCall("SetBkMode","Ptr",memory,"Int",1)
        DllCall("SetTextColor","Ptr",memory,"UInt",ColorRef(isState ? (Enabled ? "6344D7" : PauseInk) : "6344D7"))
        DllCall("DrawTextW","Ptr",memory,"Str",isState ? (Enabled ? "Зум включён" : "Зум на паузе") : TestPercentValue,"Int",-1,"Ptr",bounds,"UInt",0x24)
        DllCall("BitBlt","Ptr",target,"Int",0,"Int",0,"Int",width,"Int",height,
            "Ptr",memory,"Int",0,"Int",0,"UInt",0xCC0020)
        DllCall("SelectObject","Ptr",memory,"Ptr",oldFont)
        DllCall("SelectObject","Ptr",memory,"Ptr",previous)
        DllCall("DeleteObject","Ptr",frame)
        DllCall("DeleteDC","Ptr",memory)
        return true
    }
    if !ButtonKinds.Has(hwnd)
        return
    hdc := NumGet(lParam,hwndOffset+A_PtrSize,"Ptr")
    rectOffset := hwndOffset+2*A_PtrSize
    left := NumGet(lParam,rectOffset,"Int"), top := NumGet(lParam,rectOffset+4,"Int")
    right := NumGet(lParam,rectOffset+8,"Int"), bottom := NumGet(lParam,rectOffset+12,"Int")
    state := NumGet(lParam,16,"UInt")
    kind := ButtonKinds[hwnd].Kind
    selected := SubStr(kind,1,3) = "nav" && SubStr(kind,4) = CurrentPage
    fill := kind = "primary" ? "6035CC" : kind = "status" ? "FFFFFF" : selected ? "EDE6FF" : "EEEBF4"
    ink := kind = "primary" ? "FFFFFF" : selected ? "4E2C9F" : "393144"
    if kind = "status" && !Enabled {
        fill := "FFE3AD"
        ink := "75420D"
    }
    if state & 1
        fill := kind = "primary" ? "4C25AC" : "DED4F6"
    if state & 4
        ink := "AAA3B3"
    ; Clear corners against the surrounding panel.
    outer := kind = "status" ? (Enabled ? "F4F0FF" : "FFF4DB") : (SubStr(kind,1,3) = "nav" || ButtonKinds[hwnd].OnCard) ? "FFFFFF" : "F7F6FA"
    brush := DllCall("CreateSolidBrush","UInt",ColorRef(outer),"Ptr")
    DllCall("FillRect","Ptr",hdc,"Ptr",lParam+rectOffset,"Ptr",brush)
    DllCall("DeleteObject","Ptr",brush)
    focused := (state & 0x10) && !(state & 0x100)
    stroke := focused ? (kind = "primary" ? "D9C9FF" : "7953D6") : ""
    SmoothRound(hdc, left+1, top+1, right-left-2, bottom-top-2,
        14 * A_ScreenDPI / 96, fill, stroke)
    font := SendMessage(0x31,0,0,hwnd)
    oldFont := font ? DllCall("SelectObject","Ptr",hdc,"Ptr",font,"Ptr") : 0
    DllCall("SetBkMode","Ptr",hdc,"Int",1)
    DllCall("SetTextColor","Ptr",hdc,"UInt",ColorRef(ink))
    length := DllCall("GetWindowTextLengthW","Ptr",hwnd)
    text := Buffer((length+1)*2,0)
    DllCall("GetWindowTextW","Ptr",hwnd,"Ptr",text,"Int",length+1)
    DllCall("DrawTextW","Ptr",hdc,"Ptr",text,"Int",-1,"Ptr",lParam+rectOffset,"UInt",0x825)
    if oldFont
        DllCall("SelectObject","Ptr",hdc,"Ptr",oldFont)
    return true
}

ColorRef(hex)
{
    n := Integer("0x" hex)
    return ((n & 255) << 16) | (n & 0xFF00) | ((n >> 16) & 255)
}

SmoothRound(hdc,x,y,w,h,r,color,stroke:="")
{
    static module := DllCall("LoadLibraryW", "Str", "gdiplus.dll", "Ptr")
    static token := 0
    if !token {
        startup := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        NumPut "UInt", 1, startup
        if DllCall("Gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", startup, "Ptr", 0)
            return
    }
    graphics := 0, path := 0, brush := 0, pen := 0
    try {
        if DllCall("Gdiplus\GdipCreateFromHDC", "Ptr", hdc, "Ptr*", &graphics)
            return
        DllCall("Gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", 4)
        DllCall("Gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
        diameter := Min(r*2,w,h)
        for arc in [[x,y,180],[x+w-diameter,y,270],[x+w-diameter,y+h-diameter,0],[x,y+h-diameter,90]]
            DllCall("Gdiplus\GdipAddPathArc", "Ptr", path, "Float", arc[1], "Float", arc[2],
                "Float", diameter, "Float", diameter, "Float", arc[3], "Float", 90)
        DllCall("Gdiplus\GdipClosePathFigure", "Ptr", path)
        DllCall("Gdiplus\GdipCreateSolidFill", "UInt", 0xFF000000 | Integer("0x" color), "Ptr*", &brush)
        DllCall("Gdiplus\GdipFillPath", "Ptr", graphics, "Ptr", brush, "Ptr", path)
        if stroke != "" {
            DllCall("Gdiplus\GdipCreatePen1", "UInt", 0xFF000000 | Integer("0x" stroke),
                "Float", 1.5*A_ScreenDPI/96, "Int", 2, "Ptr*", &pen)
            DllCall("Gdiplus\GdipDrawPath", "Ptr", graphics, "Ptr", pen, "Ptr", path)
        }
    } finally {
        if pen
            DllCall("Gdiplus\GdipDeletePen", "Ptr", pen)
        if brush
            DllCall("Gdiplus\GdipDeleteBrush", "Ptr", brush)
        if path
            DllCall("Gdiplus\GdipDeletePath", "Ptr", path)
        if graphics
            DllCall("Gdiplus\GdipDeleteGraphics", "Ptr", graphics)
    }
}

RefreshLabels(*)
{
    global C
    C["SmoothingLabel"].Text := "Сглаживание: " C["Smoothing"].Value " мс"
    C["InertiaLabel"].Text := "Затухание инерции: " C["Inertia"].Value " мс"
    C["SpeedLabel"].Text := "Скорость зума: " Format("{:.2f}", C["Speed"].Value / 100) "×"
    C["AccelerationLabel"].Text := "Ускорение: " (C["Acceleration"].Value = 0
        ? "выключено" : Format("{:.2f}", C["Acceleration"].Value / 100))
    C["GainLabel"].Text := "Максимальный разгон: " Format("{:.1f}", C["MaxGain"].Value / 10) "×"
    C["GainHint"].Text := C["Acceleration"].Value = 0
        ? "Работает только при включённом ускорении.`nОграничивает разгон зума при быстром движении мыши."
        : "При быстром движении зум ускорится максимум в "
            . Format("{:.1f}", C["MaxGain"].Value / 10) . " раза.`nНапример, 2× — не более чем вдвое быстрее обычной скорости."
    C["MaxGain"].Enabled := C["Acceleration"].Value > 0
}

SaveSettings(*)
{
    global C, Cfg, ConfigDir, ConfigPath, TriggerKeys, Captured
    if Captured {
        C["Notice"].Text := "Отпусти кнопку текущего жеста перед изменением настроек."
        return
    }
    StopZoom()
    next := Cfg.Clone()
    for key in ["Smoothing", "Inertia", "Speed", "Acceleration", "MaxGain", "Reverse", "Fine", "Illustrator", "Axis", "Mod1", "Mod2"]
        next[key] := C[key].Value
    next["Interval"] := Integer(C["Interval"].Text)
    next["Key"] := C["Trigger"].Value = 10 ? Trim(C["Custom"].Text) : TriggerKeys[C["Trigger"].Value]
    try {
        ValidateGesture(next)
        BindGesture(next)
    } catch as err {
        C["Notice"].Text := "Не применено: " err.Message
        return
    }
    ; Fine mode deliberately keeps the proven physical-Ctrl path.
    fineAdjusted := next["Fine"] && !CtrlOnly(next)
    if fineAdjusted {
        next["Fine"] := 0
        C["Fine"].Value := 0
    }
    Cfg := next
    UpdateTestHint()
    try {
        DirCreate ConfigDir
        pairs := ""
        for key, value in Cfg
            pairs .= key "=" value "`n"
        IniWrite RTrim(pairs, "`n"), ConfigPath, "Zoom"
        C["Notice"].Text := fineAdjusted
            ? "Сохранено. Для этого сочетания включено обычное колесо; дробное доступно с Ctrl без других модификаторов."
            : "Настройки применены и сохранены. Проверь жест в рабочем окне."
    } catch as err {
        C["Notice"].Text := "Применено, но сохранить не удалось: " err.Message
    }
}

RefreshGesture(*)
{
    global C, ModNames, TriggerKeys
    parts := ""
    for key in ["Mod1", "Mod2"] {
        name := ModNames[C[key].Value]
        if name != ""
            parts .= name " + "
    }
    custom := C["Trigger"].Value = 10
    C["Custom"].Enabled := custom
    button := custom ? C["Custom"].Text : C["Trigger"].Text
    C["Preview"].Text := "Жест: " parts button "`nДвижение: " C["Axis"].Text
}

CtrlOnly(config)
{
    return (config["Mod1"] = 2 && config["Mod2"] = 1)
        || (config["Mod1"] = 1 && config["Mod2"] = 2)
}

ValidateGesture(config)
{
    if config["Mod1"] = config["Mod2"] && config["Mod1"] != 1
        throw Error("Выбери разные модификаторы.")
    key := config["Key"]
    if !RegExMatch(key, "i)^[a-z0-9]+$") || GetKeyName(key) = ""
        throw Error("Укажи одну клавишу: Q, F6, Space, Tab и т. п.")
    key := GetKeyName(key)
    if RegExMatch(key, "i)^(Wheel|.*(Ctrl|Control|Alt|Shift|Win)$|Joy)")
        throw Error("Выбери удерживаемую кнопку; модификаторы задаются отдельно.")
    if ((config["Mod1"] = 2 && config["Mod2"] = 3) || (config["Mod1"] = 3 && config["Mod2"] = 2))
        && (key = "z" || key = "Escape" || key = "Esc")
        throw Error("Ctrl + Alt + Z и Ctrl + Alt + Esc заняты самой программой.")
    config["Key"] := key
}

BindGesture(config)
{
    global BoundDown, BoundUp, ModSymbols
    mods := ""
    ; Canonical ordering makes equivalent modifier selections one hotkey.
    Loop 5 {
        if A_Index = config["Mod1"] || A_Index = config["Mod2"]
            mods .= ModSymbols[A_Index]
    }
    down := "$" mods config["Key"]
    up := "*" config["Key"] " Up"
    oldDown := BoundDown, oldUp := BoundUp
    try {
        HotIf CanStart
        if oldDown != ""
            Hotkey oldDown, "Off"
        Hotkey down, TriggerPressed, "On"
        HotIf CaptureActive
        if oldUp != ""
            Hotkey oldUp, "Off"
        Hotkey up, TriggerReleased, "On"
        BoundDown := down, BoundUp := up
    } catch as err {
        HotIf CanStart
        try Hotkey down, "Off"
        if oldDown != ""
            Hotkey oldDown, TriggerPressed, "On"
        HotIf CaptureActive
        try Hotkey up, "Off"
        if oldUp != ""
            Hotkey oldUp, TriggerReleased, "On"
        throw err
    } finally {
        HotIf()
    }
}

CaptureActive(*)
{
    global Captured
    return Captured
}

TriggerPressed(*)
{
    global Captured
    if Captured
        return
    Captured := true
    StartZoom()
}

TriggerReleased(*)
{
    global Captured
    StopZoom()
    Captured := false
}

Preset(speed,*)
{
    global C
    C["Speed"].Value := speed
    C["Acceleration"].Value := 0
    C["MaxGain"].Value := 20
    C["Interval"].Choose(1)
    C["Fine"].Value := 0
    RefreshLabels()
    SaveSettings()
}

ShowSettings(*)
{
    global SettingsUI
    StopZoom()
    SettingsUI.Show("w1120 h700")
    FitInterfaceText()
    RenderTest()
}

HideSettings(*)
{
    global SettingsUI
    SettingsUI.Hide()
    return true
}

ToggleEnabled(*)
{
    global Enabled, C, SettingsUI, PausePulseStart, PauseInk
    StopZoom()
    Enabled := !Enabled
    C["Pause"].Text := Enabled ? "Пауза" : "Продолжить"
    C["PauseCard"].Visible := !Enabled
    SetTimer PulsePause, 0
    PauseInk := "7E420D"
    if !Enabled {
        PausePulseStart := A_TickCount
        SetTimer PulsePause, 33
    }
    DllCall("RedrawWindow", "Ptr", SettingsUI.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)
    A_IconTip := Enabled ? "ZoomFlow — включён" : "ZoomFlow — пауза"
}

PulsePause()
{
    global Enabled, C, SettingsUI, PausePulseStart, PauseInk
    if Enabled || !DllCall("IsWindowVisible", "Ptr", SettingsUI.Hwnd)
        return
    ; A quiet 3.6-second color pulse; the label always remains readable.
    blend := (1 - Cos((A_TickCount - PausePulseStart) * 6.283185 / 3600)) / 2
    red := Round(126 + blend * 30)
    green := Round(66 + blend * 18)
    blue := Round(13 + blend * 6)
    PauseInk := Format("{:02X}{:02X}{:02X}", red, green, blue)
    DllCall("RedrawWindow", "Ptr", C["State"].Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x101)
}

ShowHelp(*)
{
    MsgBox "1. Заверши предыдущие скрипты зума через их значок программы в трее.`n"
        . "2. Нажми «Применить и сохранить», затем перейди в рабочую программу.`n"
        . "3. Удерживай выбранное сочетание и двигай мышь по выбранной оси.`n"
        . "4. Отпусти любую из этих кнопок, чтобы закончить зум.`n`n"
        . "Выбранное сочетание перехватывается. Другие сочетания остаются обычными.`n"
        . "Крестик скрывает настройки; программа продолжает работать в трее.`n"
        . "Открыть настройки: двойной щелчок по значку программы или Ctrl + Alt + Z.`n"
        . "Полностью выйти: меню значка H → Выход или Ctrl + Alt + Esc.`n`n"
        . "Скорость 1× соответствует CountsPerStep = 18 из прошлого скрипта.`n"
        . "Интервал 10 мс — исходное значение; меньшая задержка не гарантируется Windows.`n"
        . "Плавность: сглаживание и инерция регулируются отдельно.`n"
        . "Инерция действует только пока удерживается сочетание.`n"
        . "Дробное колесо работает с Ctrl без дополнительных модификаторов.`n"
        . "Другие сочетания используют обычное колесо; приложению отправляется Ctrl + колесо.`n"
        . "Программа не задаёт точный процент масштаба документа и не увеличивает весь экран.`n"
        . "Illustrator по умолчанию исключён: его зум этим способом пока не исправлен.`n`n"
        . "Настройки: %APPDATA%\ZoomFlow\settings.ini`n"
        . "Автозапуск: вкладка «Программа». Для EXE AutoHotkey не нужен.", "ZoomFlow — помощь"
}

CanStart(*)
{
    global Enabled, SettingsUI, Cfg
    if !Enabled
        return false
    if WinActive("ahk_id " SettingsUI.Hwnd)
        return OverTestCanvas()
    if Cfg["Illustrator"] = 1 && WinActive("ahk_exe Illustrator.exe")
        return false
    return true
}

StartZoom()
{
    global ZoomActive, CursorLocked, RawMotion, Accum, LastTick, TargetWindow, Cfg, FilteredRate, LastMotion, TestSession, SessionCfg, SettingsUI, C
    if !CanStart() || !GestureHeld()
        return
    TestSession := OverTestCanvas() && WinActive("ahk_id " SettingsUI.Hwnd)
    SessionCfg := Cfg.Clone()
    if TestSession {
        for key in ["Speed", "Acceleration", "MaxGain", "Smoothing", "Inertia", "Reverse", "Axis"]
            SessionCfg[key] := C[key].Value
        SessionCfg["Interval"] := Integer(C["Interval"].Text)
    }
    point := Buffer(8, 0)
    if !DllCall("GetCursorPos", "Ptr", point.Ptr, "Int")
        return
    x := NumGet(point, 0, "Int"), y := NumGet(point, 4, "Int")
    rect := Buffer(16, 0)
    NumPut "Int", x, "Int", y, "Int", x + 1, "Int", y + 1, rect
    if !DllCall("ClipCursor", "Ptr", rect.Ptr, "Int")
        return
    CursorLocked := true
    TargetWindow := WinExist("A")
    RawMotion := 0
    Accum := 0.0
    FilteredRate := 0.0
    LastMotion := A_TickCount
    LastTick := A_TickCount
    ZoomActive := true
    SetTimer ZoomTick, SessionCfg["Interval"]
}

StopZoom(*)
{
    global ZoomActive, CursorLocked, RawMotion, Accum, FilteredRate
    ZoomActive := false
    FilteredRate := 0.0
    SetTimer ZoomTick, 0
    if CursorLocked {
        DllCall("ClipCursor", "Ptr", 0)
        CursorLocked := false
    }
    RawMotion := 0
    Accum := 0.0
}

GestureHeld()
{
    global Cfg, ModNames
    if !GetKeyState(Cfg["Key"], "P")
        return false
    Loop 4 {
        index := A_Index + 1
        required := Cfg["Mod1"] = index || Cfg["Mod2"] = index
        held := index = 5 ? (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
            : GetKeyState(ModNames[index], "P")
        if required != !!held
            return false
    }
    return true
}

StillHeld()
{
    global ZoomActive, TargetWindow
    return ZoomActive && GestureHeld() && WinExist("A") = TargetWindow
}

ReadMouseInput(wParam, lParam, *)
{
    global ZoomActive, RawMotion, SessionCfg
    if !ZoomActive
        return
    headerSize := 8 + 2 * A_PtrSize
    size := 0
    result := DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003,
        "Ptr", 0, "UInt*", &size, "UInt", headerSize, "UInt")
    if result = 0xFFFFFFFF || size < headerSize + 24
        return
    data := Buffer(size, 0)
    result := DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003,
        "Ptr", data.Ptr, "UInt*", &size, "UInt", headerSize, "UInt")
    if result = 0xFFFFFFFF || result < headerSize + 24
        return
    if NumGet(data, 0, "UInt") != 0 || (NumGet(data, headerSize, "UShort") & 1)
        return
    if SessionCfg["Axis"] = 1
        RawMotion -= NumGet(data, headerSize + 16, "Int")
    else
        RawMotion += NumGet(data, headerSize + 12, "Int")
    ; No numeric return: allow the window procedure to clean up WM_INPUT.
}

ZoomTick()
{
    global RawMotion, Accum, LastTick, Cfg, FilteredRate, LastMotion, SessionCfg, TestSession, TestScale
    if !StillHeld() {
        StopZoom()
        return
    }
    Critical "On"
    delta := RawMotion
    RawMotion := 0
    Critical "Off"
    now := A_TickCount
    ; Bound long scheduling gaps: do not replay a backlog after a stall.
    elapsed := Min(50, Max(1, now - LastTick))
    LastTick := now
    if SessionCfg["Reverse"]
        delta := -delta
    if delta != 0 {
        if delta * FilteredRate < 0 || delta * Accum < 0 {
            FilteredRate := 0.0
            Accum := 0.0
        }
        LastMotion := now
    }
    gain := Min(SessionCfg["MaxGain"] / 10, 1 + SessionCfg["Acceleration"] / 100 * Abs(delta) / elapsed)
    counts := 18.0 / (SessionCfg["Speed"] / 100)
    targetRate := delta * gain / counts * 120 / elapsed
    tau := delta != 0 ? SessionCfg["Smoothing"] : SessionCfg["Inertia"]
    if tau = 0 {
        FilteredRate := targetRate
        motion := targetRate * elapsed
    } else {
        ; Exact integration of an exponential velocity filter over this tick.
        decay := Exp(-elapsed / tau)
        previousRate := FilteredRate
        FilteredRate := targetRate + (previousRate - targetRate) * decay
        motion := targetRate * elapsed + (previousRate - targetRate) * tau * (1 - decay)
    }
    if delta = 0 && (Abs(FilteredRate) < 0.02
        || now - LastMotion > Max(100, SessionCfg["Inertia"] * 6)) {
        FilteredRate := 0.0
        Accum := 0.0
        return
    }
    if TestSession {
        TestScale := Max(0.1,Min(8.0,TestScale*Exp(motion/120*0.1)))
        RenderTest()
        return
    }
    Accum += motion
    fine := SessionCfg["Fine"] && CtrlOnly(SessionCfg)
    quantum := fine ? 12 : 120
    units := Floor(Abs(Accum) / quantum)
    if units = 0
        return
    direction := Accum > 0 ? 1 : -1
    Accum -= direction * units * quantum
    units := Min(units, fine ? 120 : 12)
    if !StillHeld() {
        StopZoom()
        return
    }
    if SessionCfg["Fine"] && CtrlOnly(SessionCfg) {
        if !SendFineWheel(direction * units * quantum)
            StopZoom()
    } else {
        Loop units {
            if !StillHeld() {
                StopZoom()
                return
            }
            if CtrlOnly(SessionCfg)
                SendEvent direction > 0 ? "{Blind}{WheelUp}" : "{Blind}{WheelDown}"
            else
                SendEvent direction > 0 ? "^{WheelUp}" : "^{WheelDown}"
        }
    }
}

SendFineWheel(delta)
{
    ; INPUT + MOUSEINPUT, correct layout for 32-bit and 64-bit AHK.
    ; Keyboard modifiers are not changed; physical Ctrl stays held.
    offset := A_PtrSize = 8 ? 8 : 4
    inputSize := A_PtrSize = 8 ? 40 : 28
    packet := Buffer(inputSize, 0)
    NumPut "UInt", 0, packet, 0
    NumPut "Int", delta, packet, offset + 8
    NumPut "UInt", 0x0800, packet, offset + 12
    return DllCall("SendInput", "UInt", 1, "Ptr", packet.Ptr, "Int", inputSize, "UInt") = 1
}

HandleError(err, mode)
{
    StopZoom()
    return false
}

Cleanup(*)
{
    SetTimer PulsePause, 0
    SetTimer UpdateTestHint, 0
    SetTimer FitInterfaceText, 0
    StopZoom()
    global TestBitmap
    if TestBitmap
        DllCall("DeleteObject", "Ptr", TestBitmap)
}

Quit(*)
{
    StopZoom()
    ExitApp()
}

; One shared shortcut also replaces the shortcut created by the earlier BAT.
StartupLink()
{
    return A_Startup "\ZoomFlow.lnk"
}

RefreshStartupStatus()
{
    global C
    C["StartupStatus"].Text := (FileExist(StartupLink()) || FileExist(A_Startup "\Zoom Drag.lnk"))
        ? "Ярлык автозапуска есть. Если сменил файл или перешёл на EXE,`nвыключи и включи переключатель, чтобы обновить путь."
        : "Автозапуск выключен. Программу можно запускать вручную."
}

ChangeAutostart(*)
{
    global C
    StopZoom()
    try {
        link := StartupLink()
        if C["Autostart"].Value {
            target := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
            args := A_IsCompiled ? "--autostart" : Chr(34) A_ScriptFullPath Chr(34) " --autostart"
            FileCreateShortcut target, link, A_ScriptDir, args,
                "ZoomFlow — запуск при входе в Windows", target
            if FileExist(A_Startup "\Zoom Drag.lnk")
                FileDelete A_Startup "\Zoom Drag.lnk"
            C["StartupStatus"].Text := "Автозапуск включён для текущего " (A_IsCompiled ? "EXE." : "скрипта.")
                . "`nОкно настроек при входе в Windows открываться не будет."
        } else {
            if FileExist(link)
                FileDelete link
            if FileExist(A_Startup "\Zoom Drag.lnk")
                FileDelete A_Startup "\Zoom Drag.lnk"
            C["StartupStatus"].Text := "Автозапуск выключен. Сейчас программа продолжает работать."
        }
    } catch as err {
        C["Autostart"].Value := !!(FileExist(StartupLink()) || FileExist(A_Startup "\Zoom Drag.lnk"))
        C["StartupStatus"].Text := "Не удалось изменить автозапуск: " err.Message
    }
}

BackgroundFile()
{
    global ConfigDir
    DirCreate ConfigDir
    target := ConfigDir "\appearance-1.4.1.png"
    encoded := ""
    encoded .= "iVBORw0KGgoAAAANSUhEUgAABkAAAAV4CAIAAAB3r4atAADva0lEQVR42uz9Wbcs3XWeic35ASQAEiBaoiVAEmJJcpnoiIakJHdjuMqXoqRiJ/6Asso/wZYl"
    encoded .= "qkoq2deWfGn5ooZFgpRISXcllW8ssUFHsLNULoEk+o7A9wEgSLThi3POPjszY635zrVWRK7I/TwDg/zO3rkjIyKjWfHkO+fyZVkMAOAIfO7TXzKzl7z0RewK"
    encoded .= "AAAAAACAB8Uz7AIAAAAAAAAAAJgZBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAA"
    encoded .= "YGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAA"
    encoded .= "AAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDU"
    encoded .= "ILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAA"
    encoded .= "AAAAwNQgsAAAAAAAAAAAYGqezy4AAJiBt77pZ83MzOsv89JrfP1HweIufu/V/yr/cfQ+5ua5lfHke2ZWprAu3rEylz910z5QF44OL3/w1Y9f3j2ufIL5neTC"
    encoded .= "7pK2Tzqkvfp+rp5W3vTW+ookTmfXD7/Tf3jT8ebVV5SuFZVDy108nDz5RhfXqHCdPfokq0egJy8ZXlhfD/aGK/vcMzvBCwexZ66KXt/79W0IPiCXTlUvHgXR"
    encoded .= "unl4Ynv9OldfN/fqYRMdBeFtq3zj9NrquXhgn340Hp075dMwOH20EYp82fT4ch5eNr3hNqGeBI03a5dWQ/hMG0Zf4k1c+KXLv86tUO4P1duaNa7OkMXld/jK"
    encoded .= "i/7Bv/rfPMAnJl+WhedGADgEn/v0l8zsJS990c1s0RNp1TdqUYZDicdRdQGeuNu6K04pJYwyzwDxo1R6GOrC6GbIGLRfXQV7SDdHlrFXru2x6Akw44+86d3j"
    encoded .= "Y9lTR4J7/n3Tx5CnTY6Fg3jX7bhLcsmlZwDJgXrC+QTP4p4+GYsHaMpeBeupqavSUe6Zg0neybW/cfmjCNRVeAG/HXXlnnkyd8/d3F3yM6trs6W3Ej83l66Z"
    encoded .= "rnyb5tpoRR82RN9HDJFW4ghJ1CYuv9oTPxVuDvqdd8Rm1j6EPsHkvZsh/3WrwVp/9T/4V//rB/I8iMACgMNwMwLrLW/6Wct872eWfrTMfmmWuvun1NWDDF61"
    encoded .= "rkny+eBhBK9cXEr63a8ZvHJlWwfaq9bglWefBYP1KEoXT1xn4jPtEMErj81GvMM1dVXdW4VNzKir9WV4eNW5lroq7HIXr5tldeWVPxBvoBtHrjx/Tffkfek2"
    encoded .= "vJXrX9DkxgmZEI8njZXlQ/e5TWhIXA3bxtqO70pndRqk1DDexy929aV//9ZNFgILAA7D0QXWW57krVLqquHR8jjBK+VrLkXIHCl4FYRk1PFoUhtdJ3jl0V5o"
    encoded .= "WoHqRjTW7nnTW8uPO/Fu30xdGcErqwSvPLlbqnbJ9ZPdxcNm+ppBj5/TA/mBuqqbmigSJaurMHJlUlh3L2/lkXOvKxY3fc/LV/HWEULOtLhWRCYu1OVfqPGp"
    encoded .= "zCCw1eF48t8dGsgHLSc9su/ZGvlvbtVkIbAA4DAcV2C95V6pIMGrzIgkDF51DAePGrxSvjMkeCULncHBqyaRFNur+snbFbyyVFnyvMErV95PfNQfEbwS2nLF"
    encoded .= "LtgtsVXD1FV4Nm2pror704TiaNXg2MbqyuU+brVlV9XVVpGrrLeqLD5zdt/bGeplRFhw2lu5ftbH44UBo5Tw+E2ajbZ7ZmNZn9wHNHGzGyF2GtuBeecy28sQ"
    encoded .= "vftVf/9f/a9u7HkQgQUAh+GIAqtZXZkavOrrv5AbY2jqKh6LTRW82qlZ+zTBK1VdWSatnzi2vVWfiY/21RUgeCU8lTYErxrUld1w8KqzZrB6oPa2u7JiL2pd"
    encoded .= "XaXaXanqqrz3oxXbVF15kDnqVVd7VwumZ0jIRa6u4q1a8sUu7ZWUzHBtS4MTWTmWEuaiueNCvuu5h6d370+bXpXwTgPetbe3+6YLvyWNhcACgMNwOIFVsFcd"
    encoded .= "3ToPH7xKdhy3qwevotj5wJpBewjBq051ZVsGr3IWieCVcHhfMXi1i7qyfPDK5QhS8x4Y0+4qp65CjaD2U49r2nV15eHytlNXcSVjR+Qq9ErtkSvZW5mac7Qm"
    encoded .= "b+XxIKHTW3nTm9a2sPvuFpRb6ne6lhFT0ljl5nDJrHOXuxkeI+ufSFFe+LDFVs7Y/+Zf3ojDQmABwGE4kMB6iMGr+KVdNYPW/93mNWoGBXulfG8bjgdvIHil"
    encoded .= "tRdp+kL5WsGr6HR29VzQ7IxwvDUEr8aqK8sHr9TZGBu7ldcuX6ng1RFrBuUZ94rL0NWVZdpdzamuPHM5KK+Yqq5KZXGbRq6Ew1i4akazjzR4q/r3elqFY6oR"
    encoded .= "ZnRh3k5aWbaATZ98Mnxjbfwm3ACTOfwmj5PoOphe4GCd5Bsss7W3qf03//J/efTnQQQWAByGowisjuDVhurKkr3GUzWDhwpe5QsYMw/JyZFUf/BKGW9vHbya"
    encoded .= "t2bQ5OCVeiQQvJJ9janBK8+faYdo1r5TzaBV5gy0ijDpbHe10SSDB1JXnrlPxY3VPD7/onXLTmdpTZGrDm9l1lS23HJfq1xB8rcz776fCqOv/JedljVW1lEn"
    encoded .= "59beCd2b/qpvAKYsbYvQ0zCFVnlF/3of3WEhsADgMBxCYK1NNSgW6j/Y4NWQ+fJsUPDKhTfYJ3ilDBUJXnnitNqvbFDtbLNL8KryhHrNmkFrDF559pFmkL26"
    encoded .= "Ts2gqcGrjWoGk+rKeiYZPI66GtDoKjEhQNyFqsNb5SNXM3ur+lYlvVWTtMq6n0Zplen+1Nxf3Dsm7htSeefe+IeDpVJ60NKz6f3zLaoc2mEhsADgMEwusAhe"
    encoded .= "JceL8fhtu5rBRmfk49SVbR288lRTCZcPNIJX1whe1felK40/CF5d/qazZjBcSSF41V8z6ImjwuVJ92yjdlfu4uXnSOqqsdFVuM98QORqRFO5Fjs8ibfy+B5c"
    encoded .= "3nr9HppqT9rSViLZr7ylpZR35aS62jlp9zl9QSOkj7f+qGXJ41Y7/V7/9b/8XxzxeRCBBQCHYWaB1Rq8GtJo3IaoK3n0EM/51K+ubGTwqktdWSJ4pbzowMEr"
    encoded .= "G2mvNg1euVj+uFPwSjE6tbXcI3hlcXRG6kW1e/DKk3vG44NLOlc9U2iUrhkMVy9fM7hnu6vB6qqucuZTV/lGV0lN3CKIGyJXnj+Fa4emi2eLfC9ry5Zan7cK"
    encoded .= "B2cer644MkzmnHLfJjYNQppux237edSGd/gdH7zMQeucXkb4uiM6LAQWAByGaQXWhb26fs2gKYGPVlvUHbxSXNYmNYNG8Gqm4JVlevK2BKBmCV61qqtZgleZ"
    encoded .= "NurtwSs1m7ZX8Morv5SDV9oaDqsZ3LPd1cbqKrjbeEW6KMJiK3XlwsdXW0xXM7X8PACWmgqgeqEb6K2kIuX2mujcJc72k1b5yjx1WCjbu0EDxeRu6hpPNi1k"
    encoded .= "SGBsi1d3/FGPFDucw0JgAcBhmFNgPbJXBK/kocaQ4JUyEfaNBa+ksXpjycMwe9VRc6E8gl0teOUtp3NsdOrquTd4JY7SCV7VTrfxwav2mkELghmdNYMunzKu"
    encoded .= "mJjy2wtZsFTNYE2PTaiuWqoFLbKiA6awtKZSQdlbWezlNVHu+mWtfronpJVlGokmWh94S4MqZReN0jWdKzhEDLXlu7r7xrc2mN/cNTX/cXBY/Nf/4q8c6Hnw"
    encoded .= "+TwSAwB0MnSOPOtRV5acpSWhroJXN/V66AheRcO6ZOf4tEHQ93IYvBpQMzhD8Kq98qK6g8STa3DwSgjRCGc0wavoUnNLwSshrJcJXm1UM6irK9s0eHUVdVX3"
    encoded .= "j1dSV1G14OA2ajagk5olKlJtiLdq1vG5y5pFzazCYUN4H1aySGLmyLt+nb65tN1b0xImIcy84236XNBGi21ZkNuWfd4nfuwigQUAR2HCBNZbHxcPivcPZWKc"
    encoded .= "Bxu86lBXNjx41VHAKD62qMM46aH7yj07eoNX4ZflPcErTxyW58fiNYJXtVNhuuCVNZTLrb2DWna0T/AqXzMYHjPb1QxalBILPuPJ2l3dsrq6crXgiFLBhnP2"
    encoded .= "Wt4qcas7irQSjVVKZ6jzI8qDq7SECVsSdOue4XGn8cLIffyaN2za3ztOCOt4Auvnf26nN/o7/x26AGAuZhNYGXt12OBVXl1ZcuK4ccGrvEfLPSTrzshGBK8G"
    encoded .= "1wzaLQavpMKa1DC0016FE4MRvGp8DM4Gr4Y1aw+fJHtqBk0KXs1VM3jlTu0D1JWHH6RyaO2irvrb/9uVIlfH9FZqz9B+aZUcO+kl9w2DKFMlVn/yKN30TF3O"
    encoded .= "ANfjo5bm279F77oU3/3v/Yu/fIjnwWMIrN2kVQlkFsAMTCWw3vqmn52r0biN6jVug9qNS2OMHYNXwteABK9S8ojglfKgrZ4y3jQh0m7BK1efZ8NTe6bgVfVj"
    encoded .= "3zl4VXr73WoGe9tdWdXfNqur+m4rXzDlxk+96ipXiNpThTqigVrmiLLB3kq5ESjXfxeklY2uFhemrtE6PIqjJm9dE2W3e/PqpZ1RonxzB7XUuBuz73yFuj4f"
    encoded .= "t3MO4bBm74F1dXV1fzXQWACQvJsRvKo8zXtqJ28bvLopdWWbB6/i7rMEr/RTpk1dWTZ4JT749c9TZrvUH41QV7Z78ErVAT6gZrDsKVx5yvVALwSf6xXVldVT"
    encoded .= "V3YFdbXt4TQ+ciVXoUb3g+iq4upbWLu32ubrChslraQVkW1L091e+kVGV/XMOjjUxcTjpe7p/rYXVTu/3UEewKZNYE2iri5BYwFci3kSWG99099svGsOD16p"
    encoded .= "3/TcUPBqnLoy1V5lelh4y5oQvCJ4lRl5E7wKtvKqwSvP9NTpU1c2Yc1gpJm61ZXVtO0G6krtoaY3UGs9ljavP7XYPMZHlOneSrnveNjGTb7wamErj26T2tcz"
    encoded .= "9SuIMDZp6DAVrrr8C9WTeFsP95YtbRpyDO3SPloe9XSy33A13Ozn/8Vfmvx5cFKBNa29egQOC+AqTCKwInulNMUc0WjcpqgZtMzszbZr8OpqNYOWsVcbqStr"
    encoded .= "+Sq2f9rvTYNXrn/+Q4NX9TP6msErU+3V7QSvwuOqI3glrGRfzWDsmLYJXm1UM6i1u3L51vWQ1NWWkSvr06DxURqdoSb0ulQuvE3jAG+6yJv+FYU1fzulDEmG"
    encoded .= "GatU6mjQIHHAaCqpWnzYoob6Ix/8ug1WIDxqfv5Xp3ZYM5YQTm6vHq0hDgsAMqNDTTTovuNmg1d71AzaXMErKfhivfZq6+CV3IOs1V5dK3hljfZqyuCV+viT"
    encoded .= "Dl4pxZX7Bq8iwZRNythMwavtagY3b3c1l7oqrs8k6mpo5Eo+kGxc5Gqgt8pcbJVGCMnLu2W+IVPfP98QoJ5x1ZaSs2TeqFl6ygi9db3Tdqh39fYTVS074obr"
    encoded .= "DedKYM2vrs5AYwHsyQwJrHL8anN1ZQSvzPYKXrWoq5Y12SN41T0LeG/wqlddpT7/cfZqquCVx4+EFp10TcErEybU6g9emRDrOG7wKl43v27NYL7dVWwWxJrB"
    encoded .= "1ctVQl2ZMgvdTupqzmrBVOTqWt6qcpEf7q3qc8J0SyvNIyXu6fmJjHPCY0CqqblJU9PQs1XR7KB9fLtdtZ+lerq8n//VH5/2eXCiBNbh7JURxQKAeDwkahcb"
    encoded .= "qK5M/06vq924pftOCLfMlLrKOyPXhxipqZAHBK88uxq2T/BK3RVJSaW6M7n0VlRXNvqb+VsOXsUHUnbyMrvx4NU8zdoH1wx6uHEj2l3Nr646e7R3HkIurXX6"
    encoded .= "EEodRdHhLeqX4AIjX2PV0jZP3WYz3mq0tGoaVKi39ZY5YaIRnviHnlxuh6XxcYtK3ZO2ckrtS7zZDNbzDQAANNbiVwSvLB5dy/fXlMPZLnglDQAJXu0ZvEqf"
    encoded .= "UxsErywqZAx1UvME83bI4JXpwajW4JVZW0GWjQhe7dms3eU8i7uJ3wP01Ay6fE0UawZdOsA8tkUj1JXe9d/DK5x6COkTOAaXZ1dWM4xEeeIbuR28lVaRKV5a"
    encoded .= "d5RWJodqG8YS8a3c5X2S/fu+Qag3/Ca3NN9sKRsqobEWr381/u5f/bW/O2sIaxaBdcT41d2aE8ICeJAQvArGOXsFr5TR0i0Fr5QjrjN45dlxMcGr1l2pBq9s"
    encoded .= "Q3t11eBV2V6FU1juErzS9kC6WXt/oyKxZtDF65d31QwO79Teoq6s5kNvRV31Ra6sJbiXOIqqRilK2mVGGq3eyjvGEu6jpJWSKAtvz21Dg7wfaZxrZBsNlG4E"
    encoded .= "lXvVHobIR+yHoetwSKYQWMe1V3frj8MCeEjsoa5qI3b9eVJ69tPli6U7Pms30C2DV55qS7Bl8Eqt2Wo0RwSvysP6LnVlBK/EI/m4waubaNbeXjMYrU86eOUe"
    encoded .= "XmZ1dVXcawPUlYVC0JL2MzjtvX7RvlLkysP705jIVZu3UhuKe+rKp04esrm0Eh2QOGTTjZUnfpEpNGyZ4rBtxNKU1trF3XROtriRorqpcsLrN3E/ur26A4cF"
    encoded .= "sDXXbeL+pH6Q4FUw0hkRvGpambyJyakr075AFQdh44NXY9SV3VLwqt9eeWOZCcGr6FPcP3gl1QyGj+IbBK8KmkkVBMNrBj08G5M1g73qyuJ2V9dSV/rBs5u6"
    encoded .= "0vqI1Q5JD7dwoLfSHI/n7uD1KG1wR9j6Kxxr/FbSG1Ymb6zykwcOiS/5MPHlvQvI7MNrOCHf+a3/7q/+2ITPg/TAAgDovm2MD16NVld2S8GrwTWDtmWXCuGL"
    encoded .= "06REW/+brYNX8uSP3rYC1wxe2VB7davBq7y9egjBqwmbtQ+vGYyEiK6uLNXu6nbUVXO1oJmsrvQW+LWrveQ9Rankvd7KlfuReCuM7wWZ6UpG546Vm6C4Jplx"
    encoded .= "Xavq8fyfiNfNNos0yOZ44++2eNM9axqPyZUF1s3Er4xCQoCHwcZz5MkiaL/gVXKysrbxH8GrtrHaLQSvwrH0NcoGtwxe2ZXtVeVxf8PglbXYq4cevGquGYyO"
    encoded .= "J5fvPwPaXVm1HL5DXa2+bdACv01dWfXbjG51td7wy8VjJhW5ck98o7IeizmMtxKm5OuZYzecBEedNCY3isxPvBNfrZXxQcdg2Ud1Zu9yOj7sRcnh7SbvOPpR"
    encoded .= "5trrk4YEFgBAzFvf9HOHDF41qSvbM3i1t7qy4wSvupq1287BK9vCXjWqK2HM3Ry88vhD7w5emVbnosh0V8/eYwevymuzZ/Bqv5pB9eNfN05jawaFOQGHqqvy"
    encoded .= "vXJydaWl6rZSVx7WaEWRK6/fp/q9lXIrdOX6Xb+gBZe8faWV3DY93dLI8/3O23WT/JVL40B0vAjyTddlDyvku/3lz//Eb/ydX/nR2R7Krimwbil+dbdFhLAA"
    encoded .= "bpLtg1dDpsmzQTPl2QGDV+5j1ZU1B682adZumeCVdjx1Bq82VVd2pX7t3jY/1IMNXtkm9mpk8Moke6UV900avKqakQ1rBkV1ZalJBut7dRd1JdVgVtqHtair"
    encoded .= "7aoF1f73liwVdOmSWVpufDPzJuvj4SU/3Qs9vk1mpFVGnCRGbq6ta+5uqG7uqOkAfcRCtHvYeL/kO//dnkucEhJYAABt94cB6sqOErzqVle2ZfAqNVWQtQev"
    encoded .= "Wue37g5eKUPg9Hjac+uQsVedpRMEr7YPXsXH0kMPXlnHtG7zNWvfoWbQtQPMNZO6ubpa25/XUleutqNyLchWvCylZlRIRa6u6K1cuYYlvlYSRJB4o7FeaSUO"
    encoded .= "VXRlkez/7fmgkrz43skF9Wlc9nNDe7gjP9BStwSBBQDQcJEneNUhjFR7NURd2TTBq5Zm7UbwShuj9vVr97YZowIHctjglQnzi24dvAqvA4USmWsHrzomjCtv"
    encoded .= "b7Jm0EJ7JdYMevxHq384XF2tbMSU6krfmZZRV7tGrjxsK+3KiZ+7h3lOPVXudJ1hqxHSSoxhJ+41nloTbRgmD+vaZjYUXteusLxpHVp1zq5yZ7uqyRsDgQUA"
    encoded .= "EPC2N/3cWHVlw7o1Wb+6ssT8hFMFr5TsGsGr9c/5EMErfWQ/bfDKtLnUdwteWdi2eETwqrpzoidYSef1B69keTdj8GpAzWDdEfTVDO4xyaBVmxO17czqmRm5"
    encoded .= "zl3V1Z6Rq1SpoMdbU1+9eIQw3FvV7x6uf3E4bJIca+s0aqqxSgzDGnVJfI/w1KI2MjV+FQPU2pts53U74e/9xG/+n3/lPVOt6tUE1u01wLrbLtpgAdwaufv9"
    encoded .= "yGbtdqTglXcuYGjwKqmuTK9aEsZAxwtedamrFoXkre+uPeBq51Fj8Cp6zpqhbHBc8KqWuLj54JWrx0YieLVPs/aoEbhXLtq+umOCUI+b3AVfyrJ5u7qyYv5r"
    encoded .= "Q3Ul7kmrV19uXC3omRvz6l8IkavdvFW9c1u9VVY0EuloN5WXVon6zfw4R53vpdFVWfs3p1vrpNZpF4e83XzpKN/hL3aEBBYAQPulnOBVdbisDqFS6soGBK8U"
    encoded .= "OSO0jc+8OcGrkcEr6VyaNXhl5UZPibXcO3hlej911z+L/YJX1WO1K3hV0OndwauRzdrjmkErJmjG1QyqndpRV6LBcdspctVik7u9lZsQ4pSufvHNKiGtUgO/"
    encoded .= "TUdZ1jA9TNPAtbZF+b7qg+yIOFdjzyKzIbWrPZs8wGJCBBYAQMud0hqqzIarK2tu2CTajGQKrGlgJturbWsGLRsBk9/c2w4qby1d1H1L6sDuCF6p4oXgVfz8"
    encoded .= "X9+JFQ117OBVwV7tGbxKqyvbNni1PvdiTaXtVzO4daf2jLqKD5it1ZWwG1N7cpPIVUIlly8NLl0usmW8az/WCpmtI2w1Wlq1qKYR8e78YDVz1+scjLUMvNWl"
    encoded .= "ddunja3QJKtxVB6cwGqr77vVgkcAGHHnebDBK2V0Naxm0A4TvMpXL0pPMilzZN3BK+0ZJKWQ9g1emVyZoRyH1X7t44NXyoPKkOCVspe2Dl6Z0nJbfXo7dPAq"
    encoded .= "UFfVHTa+ZrB+FeirGXTtzC44r3gWNndJryTUlW1Qeum1W4rLZcBi2/vqQbJ1BNKavFUw54c3jRWEbxryYwOX1q5PWmVK4jKDq/xYNTUO7PMz3vfy7fWQX+2P"
    encoded .= "HzYPRWD9nf8OCQUAY7h+8CqTjBCemsTxaGZcobZd2E1d2YjglVvmK1HLNMjIBK9cKjR4iMErz671wOCVXbNf+1bBKxPt1UMLXq27q+HBK7VmMKhNu2bNYHO7"
    encoded .= "q9gDBnMCBq5zDwPYpq4q1YIW5td6I1c7N56zsrfKzXkajbVcubU0jPFcrODMT7nnlm7ilO537tnqs4ZpCjOjZR+znO4/G6aV9vJTfpxVHcaDEFiPUlc9Dusu"
    encoded .= "t4UFA0BdyVd7l5I0KfNijTWDFkzf06Wu7JrBK+X7ufCJvLVm0PYOXm1kr8YFr7xhx4jBK31CqKS9cmmHdwevhAcMKYOgnPuNwatibRDBq0heqcGrlprB6hP2"
    encoded .= "IO0yXF2pzuXQ6sqlVVi/xYrqypXZRTLTNZpcgGmd+jh3Dtavf5WrUE/YKinr61dJWVq5cHcXXU5aV/X7Jm/9Q3nMulGmaRNF4zv/3a1rKZ3bF1j3awaZHxAA"
    encoded .= "RtwJbiV4NaIpQ0pd2d7BKxf+dYPBq8Z1iMbl3nA8u/juHm3WMYNXligbvGrwauuyQU/ukI2enFdrcQ4avIrab9XM68CawVXroNQMFndmdP4cWV3lG11ZaADV"
    encoded .= "W7keueqfLaF2tCvDhvCCWfZW0ZW585uM7GigvnDP1vrpKaVUC6oGXZWwc6m5GpvUzIaiJmshd7BK47d2Od4T2Y0LLIwVAAy9gWlRnYy6MoJXpTHujQSvlKqG"
    encoded .= "2YNXLekngldylZwNCl6ZkEeYP3hlCRW6GhG80eDVlWsGh7a7chf25GVKrLwOoroKbi9zqCshuWZVdTUgctWYebSjeKvtpZVSrdgxAlH3ZFqASGOYxNKHiKrN"
    encoded .= "g0QNrb+2f9w4xp9ei1sWWNgrANj3trJtzaA1pMAyq5D6qu16wSulY+g+wau8RDPtMSo3fr3h4JV7+6nkapNe6RFOfkxKP6i4eEYKpTRWd2TKx7t18Cq6FLg3"
    encoded .= "74dU8KqojgYHr6xUF1bf9zsEr7yqjeLjatN2V6q6quzDzdXVcPenRa4sVXepnnqr2y2cd3rze8m2lEYsrgxOlMijMA7x+uUy7XVcf+vUcEo3Vtm257lvbFu7"
    encoded .= "xTeMNBrG6f0zIY59hKBp+zBuVmCt2quf/7mi1VptboUCAwD5xvdgg1cj1VX0NVg4aMv00W4YQY4MXnWshjo0dukvqx91WiE9gOCV5RTpMYJXJpb1JZzu7Qev"
    encoded .= "6ifh3MGrGWoG2ycZtFj/iZ7lMOoqXS24R+RKNuYjvVV0eUx7q4S0MqFPZHLwEw3DXBz86IPDdvvUnVNKdvmydHXjxoqouTXYUR9spuWZB2WvrNyFHVcFAM13"
    encoded .= "AY/tlZ/duT16zf1/uUV/ejrC8HjxLtgrXx0znS5jiL3yu9F+dmWCgeXKULIjeOXra7Jd8MqVXZu0V67aK/eMQvLyzwpPLJWPuv7WHsWg2uyV62WDsr3yofbK"
    encoded .= "S4qxWlajlg2G05DV7ZWr6Q8PjvbCiebV07ysinzNynjxRLrYaJcuBL62/V650EXX5dXglWKvLjfE1z5prx9d/tgeeHxdurdeXtyZ7p62V766W5+cp+6VHehr"
    encoded .= "V5rL28vTfeH3/rN2M738i8rec18/WQu3ay9fHh+/aOXI9bU/9NNPwq24G91XjujVT/PsHbwwzPD7O8dP3sfXLtNrx9ijK1rx1Ftb18d7yC9u+ms/vdwJfn+N"
    encoded .= "zxbva//2wm55fC2K3vf+jnK3wgd7t5jialz+rHbT9yd79nwFvX5PPPsDUYyc/M8vNsbXX7j2d8Xfrf8iKXDU/3l9baYRUn7xkVX+Z7n/zcUNJrAq9ur+f1++"
    encoded .= "rGeaQgB4mOrKLNdo3Bq7NVlvuwS9uKvqPpS3yqgrI3iVWI2CEkivwzWCVza6bHCC4JWN7tfeELyyfNlgU/DK9BniU2WDvcGr8gHT1699m+BVfQKzvuBVc7N2"
    encoded .= "tWawslK1dlfDaga9crhYrujShYN7YOqqObNW23v1u1x8xqUiV9lSQXHuS+laVq1kFG8D0n04mRd28R2FO5dYta6OqeKOmE0DD3WsmAlZjXjFoD/a0tD4Ff7y"
    encoded .= "1rm1BFZor+o/JIcFAPqdxS09Td529sor7ca77VU+eOUPL3jlRwhe+bWCV/EHEZxPVw5exceZK8ebD7VXtWRBYT1aywbLK11c3nkGRLRXueCVi5s/R/DKa7cG"
    encoded .= "14JXrtmrYvDKrboaXg49Fe421ZpBl0JDF1ma0g4s3ct8/TJT23uXAaT1FehKXXlrZs082nsrO9Dvr38xcuUNkav1AI6ff6AXAaz7q+hR3soLCze73L71U6+e"
    encoded .= "C7sfPyq9kZ2lqUq5q3v7xKOYlRWTR25R+su1FMzd5j3el/X4VzkbFY3WvLYX1kNWpod6tNhPV1aoKV/k3f9rXyg8CIGl2yscFgD0qKvaw6OJvsPqNYNSsdXq"
    encoded .= "s4pgG1y2RRYV4EgioSxi3HPqysMfrCqF8NPMVEd5Zlaek1GesBrxEeVpg+aCgREEmyeyMimLFJ9PQr92r6q+urVUimUF6ZzotFIVTd1lg6W95IUTpFTW54VC"
    encoded .= "Rw+OJykGUiobLMuwi4uHtPme6dd+KQ3WD3FfnWqw2GLJiyVvtlY4V74g+NrHs+Y+Vo47rx9apaq3lVuAh4fQZQ3Y5WesqCtbu3xeXojGqCubQl256+Lvolqw"
    encoded .= "pG8utFKp7nK9VNCrjvh0J63awKHeauUyVfdWl6+oWJZ6seCJqKlLCb80fAVjZXljZfd0lQflfbWqPFWteLE+TZFcor7RxI42QC/+sVtlY0ZU2olLtc3/5wP+"
    encoded .= "d29BCKxZ7BUOCwCa1ZUn1VXsGjYMXrkQvHIheOX7Bq/qP/IRwSvXglcW2JMgeOXDygZryqE3eNVYNujK8TMyeOWCL3XJJbkLM02aHLxyIXil1F4Ksw36vGWD"
    encoded .= "44JXXtOVXgs6RcEr7w9e2ebBq/qBVyl8u3hO9zh4te5DleBVyb+EXwWINYNyu6sR6sq3UleeUVeWyKzVzjU/V1dFPbRmD2reyk1rceUFb2UjvVXhlnG/11NZ"
    encoded .= "Wq15q/X+V5q0WtVX68bKTo1HLGj8DNXe5AJNp+tSaJaVU0tef4/WyNGppbnUeYKNansAkASbT/C/lpWvdSFDYM1jr3BYAJC8eW3T8Wps8Cqos5BskeVrBl1W"
    encoded .= "VyOCV1bRf7JHq6uyfPVi0tIV1UbVxowOXskrsG72/MDBK7tS8Moa+7Wb1q+97vhctFdlDx9ONlHdIW49wSuXg1eWCV5ZMnjl4aWvN3hVOvDy6aHg0ErUDHoo"
    encoded .= "iJP+pbgDL2sGo07t6zeqyzxbpK5MCqwl1VUo9C/DSJ7ZdcU+956NXN1v7l72Vl7wVsVVOvVWXvBW1u6tLooEy2+xbo6q0sqr0spWpZXp0qo8LlCE1WVNX1Fj"
    encoded .= "rCaFamKpwTHV3kAUIeeruc4WciUMUc1T+TemjvHI3GAT95S9unvxak93AIAN1ZU1T2ica9Zu+RmXXXirU5Eg7UNx1WNnUPt1v7qyHnVlWl96bRZIi9RVtA7C"
    encoded .= "QerZQ9rF48fDQ7hdXdVOsDHTpSsHnvJ2JgSvTA1eZY+lh9Cv3ZWrVm2tPDhP8sGry1Xw2soEwav447F1BRPs0oZm7VZXV7H+kzq122qL89quU/bbmCb3cpt2"
    encoded .= "l/qNS/tN3HUW9rmvH3vxyaVPFxAcr1681XlqwOPF81K8KymXZunemb8Xp25N1U2LV1japLbG5556detYqHf03rWRuz1jzPs+CwJrEy5NU8NkgqsOCwBA0Dji"
    encoded .= "kGLjqQbjSYXGqyvtRdHoVNqHLozQMh6t4TfqUHX8VIOWDH8Jay2vwPrxlHz37e2VcAC4pI/Cfbdt8MqS9sprp0dbv3bFEOXUlZXLBoXVS3W8GmqvqlvmFYOa"
    encoded .= "n2rQ6+d4Rl2J9mqUhXEr27ryDizuPVX8jZ9kcM+dZgnlZ7L1s/o3WOK8imt/KxrA4EI7h7dK3Aq3lFYdxioYD0l31gaRIX2ZuaNF8vQv9hVDNxR6mnFTDi+w"
    encoded .= "htgrHBYAjLJXKXVlNx688tSqJ5yRZ9dkiLoyglfC8TNMXZkcsEskoUYEr6KPeWTwyoLikZryyakru1rwKjrY9eCVoCo0dWUbBK+sqLYaA0StwSvXjlhxnkHN"
    encoded .= "wgwMXmn7bXRabTvfZ53Kr7LfLBf3s67IVdZbuXC5EE/HcHzi4pXTSpNmaE/y4VCxcRpoa/vKJvHFXmaEMODb3AHGZKhT8Q1fja9CYCn2qpNH8guNBQBtF3nP"
    encoded .= "/CClrkxqVRXehKYKXg1QV5b1aPJvLBmwd0mjHSx4ZZVIh/Lua0fNQwheWc5etQevbJaywf7gVWlTjhO80j3CJsErqRJzoIiZtmYQdZXcdSZXqhZWxrUq4Np3"
    encoded .= "PFVv5dLCS59EfCEOrqOt0kr95kc0RaKxysoHdbaa/OBtjCTJyxTvWcoNyKmnm7DYDXNggdXTuL0OUSwA6FZXdsDglaRgtqsZNIJXoaupr4PgZ64YvLJUpYaw"
    encoded .= "+M3s1bjglVVLCfvslWLzpLK+6p5pLRssHT6dwatOe7V6sg4IXkXPzUcJXg2tGTSp0K+qYJLtrrys28qnpF91jyXVlQfWyCoHuBi56vRWVlRp3n4pi11/+WNM"
    encoded .= "3NbnklbSACdjrBIdv+RRxzAXNGbsuZOi2qlN+xFWE4E1jb3CYQFAt716sMErZfT10IJXmT4XjcErtUluq73qbPaxUb92V3d7T/DKtisbrM6Ynj2kjxa8smFl"
    encoded .= "g3Jrnq6ywV1TMH3BKzHINkGzdq/0Sh/Vqf2Q6qohqlbfb8Kuk9WVHPer3h/dBtY+t13HVt4z2dPQ9ADTKGMVZqjLe6TDVVm+5jE/Mhs5meBsXufmqw7355AC"
    encoded .= "a2t7dbdAHBYADFRXZrle45uqK9syeGXWbK+UKNv1m7XbZsGr1GpsGLwysWxw4+CV7Vk22KWurND6OHGc1+VV/ZFsgL3SKvs8kkTCUeTVk32vskGXL16uHRkE"
    encoded .= "rxIZor52V5K6qixgDnWV7NG+VbXgFqWCu3ir5rBVz0QcA6WV9w0Fo7FEQ2/45sGkMD4Y7HC2WzJOCoF1YHu16WIB4AHaq8MGr5Tx027Bq4xHS+aQNgpeSfrG"
    encoded .= "W9dBkzPzB68sUTbYHLyynfq1t9srT5SmBPbqlsoGXbzQzBO8sqYszOjglbtyPW8JXnVNDjiwZrCwx2rbmNldHh51PkxdNUf8WiRpudZybU1cts/FS5grF/kN"
    encoded .= "Q6Pnb9h2Sbd0ele5vKmX+ubBZUND9JaMV2vD+GgMceXh/s16qqNv2MEE1p72CgBAtkUHDF5t0Kzdmj3amOCVUhlI8Ep8COgIXlUfj5qDV6bZqwHBK+ssG/Tg"
    encoded .= "JMk8+V2vbNCTO0QvG/TM451UNtgcvKo+1Y7oQHQDwavyDuyoGbxCu6sHoK7EakFt+r9UqeC03qonbLWTtBLnOBRb2UteIiFofDu15LmV3mr0jnU6JEcSWNgr"
    encoded .= "AJjvFuLC6KD7a7eR7cZtXKuFIcErZQxG8Cra07n2rD3Bq/CguEq/dk88cUzXr93T0zQ0B69szrLBbYJX1tyv3TWpOagJ0dDW41fQMeNrBgNDN6zd1az7Kl+a"
    encoded .= "2qWuOiJX7qnW7JlLVn+TPhvXuDAhfTzRKjS+R2e/LK0trqGmUC9gVBe6VQ/144SmxnQTW07+HwILewUAoN9ebjJ4lVZXtmHwqk9d2cDglUuv0gcomwSvWiY/"
    encoded .= "Eu3V8OCVyV/Db9OvfWjwKnh7zz/uRP1c9i4b1KZEPFi/dpevOVsVczUEr2yfFk5B8CpRM9gXvNqt3ZWHR/2+6qpZj4rVgjtGrnovVtr1pNlbSaOsraWVaKxU"
    encoded .= "x+HpgsLmPJTn3qdprUcsfKtFXrUFV9+bH1l/HUNgYa8AYDJ7NVJd2a0Fr8bUDOYmPWwPXik7heDV9sErUdUktqAleFU96hL92gV75cpDxtGDV7U1LMqbnrLB"
    encoded .= "nuCV7RqKEYNXNlELp45m7W17LNxdG3VqV3dUdSLFgerKK7alqq7EasExYcleb6VewKOWaMolRZqJuL481xNNtev8mDiRZ8JObZP/eePv9KHlADG021SGN/hU"
    encoded .= "g8Aaz+WEgNgrAJhFXVlDt6ad1JWpPZvsFoNXrWuiPWTL6soOHbwyJQB19eCVMCa/RtlgQ/BqNnsVdOby5v1wzbLBdPBKlQvWWQRnkwWvNmrW7j5AXV3uK6Eb"
    encoded .= "faz5NlRXFhtiRV3FIalKTq1+ztZWw+WzNTEiavVW6mhBlezC5bScZE2IoS2NlaartDdIuqo2Iab+wXbTF96YGVqOb6VuTmCdOSzsFQBciQcbvFIGpNrKCOOr"
    encoded .= "2w5epVajO3i1qbpK26tB/do1bSLu7bi21lOH6gZlg56/2qTKBlv6tZuUfxvfr90SZYPVVRJzMfs10m6aO2/lWNoteNViZPaqGWxKqJ1v/6TqarNqwd0iV5t6"
    encoded .= "q6Fhq6S0MpNle8/M1Bm/1KmHvG2p6juNly0767Bd1nnfxSCwNnJY2CsAmOUWQ/BKWJ/MFM+e/W4wNfPevsGrUEFo66BtfZO9anJna7/31Ft3qSu7VvDKKBus"
    encoded .= "PRJ2lg26uApb9GvXjoyBDYlmC17JUsZSwatuI+Nl0TZcXcWOb351NbZaMOgi1x6QrLYM28Bb5cNWbtmvhfSRYON3nHK6yvp6hPsIUWUtgbKGhc/la5gfEIEV"
    encoded .= "OCwAgOvfmzrUlQmpGMmFhCOk3o7jverKEsGrpEfbMHjlLu86O1TwSrdXw4NXg+xVLnilHX5zBa+MssGt7BXBqzmCV6PaXUk7KmxFf6vqSqwWFE9StYVcxltZ"
    encoded .= "bL0bvFV0Z/Z5pZV8c1ZHYNLIrt80+WB149nt3FFIXU9SLZu8FIEFAPCQeBDBK+WhuVVdWTZ4pYx8WyNgOXulNbnoGiY+gOBV4YXiAenWF7zqsVc7B68s101G"
    encoded .= "2TlNZYOufAy2Wb92U+u5TC4b3D94ZVr/rE36tW/Wg/zyQ2uQfaqR8cpui/dS6ySDSvP+qdWVPPtBe+RK7B83yltpcyeGl8045FTv+9X9JVC8JP0XHR04MwPf"
    encoded .= "boXjQ1al3UEdNCrlHS9ddnlbBBYAwE2qK9sneOXq+mwfvJLUlQ0IXu1dM2gTBK9SH4psrwSTePXgVcJeZZ6qeu2V13ea546o+YNXdpCyQZc/yJ37tSu1XYng"
    encoded .= "leXbkFeDV4ryC/fYtDWDqrqqXEzGqytxekGvfaaRuhJPz83PzdBbSVeMuL7OQw+jmCBRWiW+ivN0bEoaDaan8c0PWeO/3kgb+eDX3Zi2GrWU4+S3EFgAAA33"
    encoded .= "gO5p8qpCIaWuQq/QqK5sdPCqr1m7EbzKjl4fXvDKDl822NGvXbJXntwnetmgZ3bA8LLBSfq1u3ZlaSobPHbwqkHztairyt2zYH7c49upR5fCIerKtatApK7U"
    encoded .= "asEgclXVLV6fYi+44nd4q+BGFFypm8JWXdLKo0ukOOxQ/zRZ0JefPtBTqz3e0mzmp3y6BXWxHHrtpxZYt9qO/W6qRAC4VXv1gINXcvstYaRE8Co4olxfh52C"
    encoded .= "V1326rrBK9uobDBY/0GzDd5S2aDaT6f+kLxv2WBL8ErKE9kNBK8aquG2qBlsaHflHh9dXerKLGrmlVBXyiyKmrqKTszqhcG1uTDm8VZNYat+aZW8Y8ZjBm+7"
    encoded .= "dzfpKjmDlZ11ZxuLspV0OXKY6/Z7ypPAAgBI3BUIXlX/vrP1eP3xW/oQ5OCVCx/nUYNXpkz/HSski6YEkDNQncErG1I2KKkr0/qzTVI2GNqrzrJBizTokcsG"
    encoded .= "XXs8dq3jzmb92lsm0WtQMzaiWfsWNYNbtLsapq6sLOv3VVeaVm6vFmyPXDVW8jZ7K6/fN711NFC/m9alVX7E4g3rIN4iMwMc6dftrmSLZZp3/r6Dh9I/HYEF"
    encoded .= "AHCj6so2D14l1FVioHDl4NXhawYta9DkD+2owau0vaofMd56BO5WNigFr0wqGxTUVX31g+eprrLB2hqqEQ/dXkkpj5bgVbkIztr7taf7E8lFXuEUgenglTXW"
    encoded .= "xIXBKxeOb0/upS1qBj30D76m9iZWV2E/r9LlKBO5SpUKxl9iXclbBXdJD+4r3jiEc3kFe5xMfGfILXGUqGqZNXGEvNo+lDT8HZaeN79xnYbAAgAYbK82VVc2"
    encoded .= "XfBKVVd268Gr1Gqkhpx5e+V9h/RNBK8szKFtELwSMnXD7FVH2WA4vdcBywbdxLW/2bLBaYNXV6kZvGl15dEpcLrFHp6M0pdF8R7b0luVrkRRrFU4tbSxiks3"
    encoded .= "//qwbWtjlXdVDUNQdUA4Wuj40SrjfP+/X7bY+zO6sGsKrNtrg0UDLIDb1FeZ34eNGOJH2UHqyqYIXg1RV9bu0XL2iuCVNQSvNrFXO/ZrH2GvKs3ohJq+Xe3V"
    encoded .= "pGWDsr3qqVEaWDa4Z7/29uDVwI5Og4JXoZrZq2Zwc3VllTbtZR0yUl0Nj1xtoq7qX5cUr3ZarXRweiqjFB8jrbIxKeFdvElXWS6uXnjnkSrJW7bhEAZq5jVe"
    encoded .= "jr0bSGABAIy5XUwQvGoaDHl6ZcYFr5Swyj7BK2UkePXgVaRBxwWv9HcX1ZV+GCj2qi94ZU1lg7392m3eskE1eGWV7lSCBE82vXqgZYMj+rX7qluq7rSrBK/6"
    encoded .= "awZDKVPYLtfV1eVCblJdtUeuCufTJN6qNWzlbYMNV3qgRnf0vElrHrBFg6ZugeGZLdzD39x+e3NRUPmAZTxcgXVLISziVwAPVl3ZwwpeJbTAdjWD8rBMcTuh"
    encoded .= "vSJ4dZWywfbgld1q2WC7vfLwk20sG1z3N2PKBi3oDy2WDW7Yr32fssHyDtxiKj0X7j2Z4FXZzkxWM+geXJM89EAXJ9tG6irMlPWoKzFy5XWn5MHFz6V7ZYO3"
    encoded .= "8vhaun6V7JRWynBPv73mv1mUBmn1C0yL4vHG340WTQ/GTO22P5aZ9ykJLACAedWV0G68XV3ZsYNX42sGTdF5BK8SR9Dg4JV2EB6xbDBeZ61ssLFfu0XdsWYr"
    encoded .= "G7RqvVJkrzw+R9SyQSF4tbIlG/VrHxq8Kj6Xjw5erRzZieBVIcczXF1dfg5Va+mj1JULp4xLqlcaqXjtgNPUVX3m08m8Vf3yLfR31wJG0l3V9XdP3d+DcVnz"
    encoded .= "tIatvqTRj23pUjZY9qK/07Qxp6mV4PUF1m2EsIhfAWCvhturQcGrATWDRvDK5gpemVInZ8orrt+v3SphF30c29yvvfYMcwPBKwvLBi1uerVF2aDXn+GGlw1K"
    encoded .= "YSKbs2zw4QSvZqgZPI66inq0F47T5mrB9siVWiroyUuc1asEG7zVXtLKU2+duqfXBmJt7eEzL2qfZHArBXYVkeN9Lx0jtW55IsIpElhHd1jYKwDU1Vh1dcDg"
    encoded .= "VWMvUs8MzGYKXsmrIQ8uDxG8Msl/JoNXqr3ycLC+S9lgZfcLz13zlg2WdoVur0aUDcb2Kl82WCvyaQlejSsbHBm8ih2NaXpu3V5lg1dpQeOb1wx6dJ/tV1e2"
    encoded .= "Lh/nVVfN1YKdpYIeHI8jLm4WznOgSSvTWhzGIyv14i/rKNO/+BnrqrqmGvTWlbmajbry00azpOrZ1tnl1ywlhMd1WNgrgIemriwfN8mEoF1IMTX1Ab1m8Epp"
    encoded .= "Z7pP8MrVPVX71+DgVdofeesKFI7HOfq1e8tHnwleKc8z0XPFDmWDru+fjcsGvXKJ2qjpFWWD1cf/OYNXoaMZ3qx9h5pBj0TMSHVVvrDvqa5cO9u97qtuxlsN"
    encoded .= "kFYuX1RFI5WYnLdFZLTHwtrHbJsKn4P2xVr6t7zbR82+6+iBBQDQb7MOF7warK6sK3g1a82gNQSvwuw+wavyE1/2ox9dNqjYq33KBrexV9cvG6z9bWvZYJO9"
    encoded .= "qiVvrlE26HX7otmrTYJXpUNlr+BVU83g9urKap3aXbhMjVdXiR7til2tXoK8dqnrVFcjvFUuT1rdf/EYpqeUvnoj1FqrZ+fhUT8xeUS8Q3eqB9Wg3Udu7qIe"
    encoded .= "FMvqfyKwBI4YwiJ+BYC6ksYH+iBg8uBVt7rK2yvXP5kbD17FO2OT4NUm9mpQ8MooG8w/6W1XNmi1gq2jlw1GambdXVyrX7vXfMv6zr968KrWjHyOmsFp1ZWb"
    encoded .= "CwenKRnUxshV/QSf1Vt5/e03k1YDjVWm2VK7axookrKljlMO/g/71CK8cPGq3kJgFX3QITQW6grgwdurYerKdBWWV1d2neDVPDWDdvTglUllg3IVZ7IPmqos"
    encoded .= "UkV8N1I2KASvrKlsMD6gPLlbussG19NHY8oG6xfMkoux2ywb3CJ4Zfmywa2DVx71FcsGr7I1g16/MnocSqrm7LZSV2q1YOUmJkeuos+9FuDx0pG0gbcqXbSq"
    encoded .= "zd0z3+JsMmmJSa0pGoZwtQt2cpzbZG1806V3aqW9PdQyxSIG7KT5BN6MJYTzR7GwVwAPW13ZjQavlADTjQWvlBgWwavmk+HoZYOVR6TN7NUOZYM5e5UsGzRl"
    encoded .= "agYpeFVxMdZfNlh8tm6yV0q/9sJ8hxl7NbRf+1GDV7V2Th6rK4tqBqszJ4aTDN6CunLt/hFFrlw4rxXRtX4f8eQwpi1stdFMu/qwTy9AzMarmm3SXo3dp9VS"
    encoded .= "m67ZMnbjFjN781/5n5/99CP/n987+nPZpD2wZnZY2CuAh22zCF5lVqZFXZmeeFJqHRPaiOBVQl1ZOga1bdngNsGrMWWD8UTvW5cNho85G5UNWnvTK69cgqL6"
    encoded .= "zBsoG3TBUw7v1+4W+NSdg1fZZu3ZmsHLK369ZjA8Sg+orhSpGqurLSJXg7xV5t7ngrRqvesNMlbxrLttw6HoJY25nF65tEODrUEsu65U9d3e/Ff+09a3OUT/"
    encoded .= "q4kFlk1ZToi6AkBddZuXFnWlDh7C3tHZDRscvHJhbJaZo2fD4FUm/yXstKy9OkTwagN7NSZ4ZTuWDXbYq1nKBsNnv42bXollg6Y1vRpWNthgr2YqGwz7tW8V"
    encoded .= "vCqdPFHwqr1m0KTgVbZmMNvuqrbDR6mrtYOy9Zgsq6trR648XNdtvVWftKqc7C2DxvDekB6GSXewzBK2VlQT5av8muu5VN7tB//yfzpoQw7T7Gv2WQgn0Vio"
    encoded .= "KwDsVe/9v9VebRm8UiZQbFoZ/Sm+yRmlglcpe7VR8MosOai9UvDK5Gq5nEiK1jcqG2wLXtleZYOeP+67ywYtmVywZNmgsAeaywZtv6ZXbtIMAocuG/RIhc4X"
    encoded .= "vHI304NX6ZpBq08zqdcMNnZqD72qVz5zbdrKwkYF5j4M8dnoyNXk3iqQViZ/d6iPu8bN72xa26zEnVYaJA1QP1ezJEeezfB83X/wL//PlD/7g3/7+zf5TPb8"
    encoded .= "Q6zlfX+0m8xCWgGAbK8ebPBKazt6O8Gr0DR0qSuTWq9q6SdPr8DMwSu7xbJB62p6NaDP8ZiyQRvY9Mor156GssFIE9iQkEtFFkghl0TZ4CbBK+vq13614FWq"
    encoded .= "ZrBwxFZNnN+auooaXSkzV64er4IZL753zltZ1O9TEUnlOR5cHyuYjZBWGxorz1cYDmmr7v2LaH35ZnpqmWgpobf6g3/7/214jDhZwyPUER5DYOGVAGBGr5VR"
    encoded .= "V6blnRK6ZX3okVFpsh5pjTspgxlPfB3oHWsSi6UHHrySlIWePHeT6h68MXi1p706ZNmgBV1jtiob1OxVrmwwslfXLBs0qenVVfq1hzsqHbwqHRjbdLwquCG1"
    encoded .= "WbvXbcPodlceXcyvqq7ERldauW712u7ynSCK5YVXFWHiDO12on1HkhtreTQoaR9iJW44XQPX5nFIs03yAcvYbKzfba56t+YH//Jf1IxV93YeIah2PIEFAHA4"
    encoded .= "e3Wo4FXTyrTYK08l2T3T2yHVffSmglc2omzw6sEry5UNWtitODjerlE2ONheeea0KfeyGdz0yiu6JXoYdW1H71s2GDcY8trD9freK8uCZNlgR7/2qBxy2+BV"
    encoded .= "WIW6ac1gpt1VNHPlDairaSJXsbcSBj+eniS4Q1pF46dQWmnDxNx8g96kI3Lr3ax/jljT59v9wVr06QfWvNUf/tt/L49gF+FNjgcCCwBgQ3VlBK8aB1VankZ0"
    encoded .= "OTWxNEHwKliL6wevmuxVb/DKGsoGi3+zWfAqMBHhi1L2KjPNfLZs0ESRmS8bDOzV6iP2JmWDDb6gsj+bygYTvmCzskGv3J9aglcXRX8eHFpXDF511gwGh6WH"
    encoded .= "ndqvo66UKT6bqwWbzt/i7rKiud7WW1WW3iOtuqYhNu37zz5d5Z1/r01yfR1xtM1qjGIpreIP/KW/WPqbP/x3/z7vn8Rc28G8FgILACB1K3D1hQOCV0qkfRN1"
    encoded .= "ZQSvzNqCV5ZtjTFP8KpgQnR7uHHZoLd9nnG/9r3KBpVd5EPKBm+/6ZUW2fD5ygZrx93gfu1mYdlgZ/DqcglXDF6F8+jVg1ceeRnPqisLJK7Pqq6U6RFMq9I1"
    encoded .= "LepYGYj4Tt4qMbLaUFq5Pt9gOLQTxkfe8IdjDNEYm3RLTdkf8QN/6S8U1NV/uHdClmXT8lD2JQILAEC/umeCV8nc9PWCV7upK5smeJWUaLJT2iJ4FSukXCuQ"
    encoded .= "0pOqvJGlV3eqK5u3bFDYY9cvG7RZml4NKBvM26vGssEGe3WcssFsv/Zw59TLBt2DQysfvKrp2J5m7UGwKKoZzHZqj4+fbnUVTC9YOKza1JXY5SoXuerwVm65"
    encoded .= "4r12aWVyD6tEAwFvCvXrA5jUqgxQHXOaqSHL2zyjdGmvnngreXO8vNq3UTqIwAIAyNz9ZqkZtBmDV8oaEbyKni7b/NFmwaucSJqvbLDJXg0sG9QKa2J7lSob"
    encoded .= "7G96VTVNw8oGt256pZQNKk2vhnQayogDL2nC65YNBsGrFUPkFe/ggW7sCl55ZDY2rRlMq6vSJeiK6ipTLTg8cuVyTqjUO2ugt8pJK3UMIHx5pd2Lg3uUJbtA"
    encoded .= "yC/t76k1Zt2u8BxQcFnNK/39f+nPl371R//uP1wueelZ7dJaLoeUWwgsAICh9mrz4FX3N3W71wwKKx0uT1uTaDSbWI1tgle1qZbUMWvdXuXn896jbNBbqyY2"
    encoded .= "C14lyga9vrske9VQNmg0vVLOnKmaXnWUDRY/7UzZoCmzDXp0Qbh28Mqi+se+4NU2NYPZTu1au7TN1ZUiiEV1Fc05eV1vleh9WRHqTdJKGRtmjVVC/7TpqtTK"
    encoded .= "1l9yI3MJdi1rUe3VH/27/1E72Jah2+KR1JrOcCGwAADG3MpuK3ilKJYhwSvFMGkRsGDv3WbwyhJlg/MFr+opnentVX/ZoKWbXpVnRXR9V2xprzyo92lt2T6u"
    encoded .= "6VVcsaXYq6uUDVa3bkDZYBQIOk7wasuawciijlZX+V5pDZE9i+2wW1Gdh2eYdpZZvWWhfg9Le6tKB75NpZU2bY5aMZbTKsEALlNQuLuj8imTWou+M7//x/98"
    encoded .= "WV0lnju61irxoU63vxFYAAC96qp6Ox1S9WaTBK9qzxctw5qjBK961RXBq/ov5S5UzfaqqiasLGPKH9HVywab7FXp9O2xVzfe9Ko4dd1gexV2uG8JXlmx27ol"
    encoded .= "ywY9mq8sHbyyQlNHl9WVjQ9eef34SdYMhvL0kOqqLXJl8RcIfmVvpYatvHEwqA/AJK2U1VXZKRD1wUnX4LnHzcylVF7zKv3Fn/jIF87//LUrf/7Nz3y+Q0OJ"
    encoded .= "u/OQzbEQWAAAXXeFOYJXkUvwjpWRnpYz5kIdYA4IXqXW5OrBK/FoSK6Ai81tcxkoz7+v6DkmDF512asrlA3O1/RqirLBirvct+nV8LLBdcW2V9lgkJzSg1cp"
    encoded .= "e5UPXkk1g6YGrzo7tYclq8dSV8MjV65crquz2nh+fFC513tOf6Wkldp4Qhc73qSdFLnWr0sOrKgujNUrt3+LV536rD9eF09dDuqQhguBBQDQfrm/oeCVolgI"
    encoded .= "XkXjeNMewFV/ZPsEr2xw2aCL/Ts8d9aMtVfys4r0lLJp06uRZYOBMCo/DRpNr1aeqzuaXm1VNjhRv/Ytg1crab7G4FWTurJUzaBX9/A06ipdLbjekEqMXHX2"
    encoded .= "5hvlra4hrVwebmV1Vas+yhil0Yqqc3U61zsjZ573mldc2dqcKrNv3fksoUH7MnrPIbAAAA6orkRJpasry/ZsssmCV0l1ZelQuxy8yq3JRsGrbns1OnhllebH"
    encoded .= "8jHcFbxqLhv0lo8qWTbYaq9yZYPFE2nrskHbrOmV1WeCHz9z2ZXsVdAz+wGUDaaCV1q/9s7gVVVdmRS8qtcMrh85crTNs3WmUbHq8OkpTWt05drNzZXLVLHM"
    encoded .= "MOWt1G+cqiE50Rzlv8NoGJK4qgnUYkV5ONrlLDRxNtiA7N+O/XmvVtXVtz7ztDbwTT/+Q6uv+eiv/U/VZZy4pueVc17PK/ms2k3k8h0oIQQAeCD26hjBq151"
    encoded .= "ZSODVzPWDNqhglf6ClyrX/ucZYNy06vZywaj81G3V2KDKitOGSZ+qm32Sp28zLVTI2zZ7sI1JGx6lZnuzculdjUZMbZsMCyojOxVol/7dsGrqoCrp34G1wx2"
    encoded .= "dmovuM4p1dXgyNXglnxt3irepuRta6C0kkdh5ulfZFyWNy9hPzk1amWWhLH67BdWV+FNP/ZDSW+1vhX3jZhVU2CPfNaKxhJHwesia1K9hcACALiqurKZg1eq"
    encoded .= "uuq2V/sEr5SOGlsHr8IyNo82fkzwylIVfJ3Bq8OVDZoSprrFplfD7JXXJwlo6AN93aZXGZVg2za9Kjd76k8Graqr0hW8vWxw8uCV13dv3O4q2L1HVFdqteDw"
    encoded .= "yNVVvFXzdzza8GCMsUoNRnNL6pncMGOYZqxNe96rXx4Zqy/Wd9+bfuzPnaurX/+PZkttc2VNFPqsu1jWk1cubZ/NkxWbtF8ZAgsAQL68J+PY8lzLaXVlUwSv"
    encoded .= "hqgre5jBK2spG8wPjvuCVyPsVf0xYsuywQ2bXlUOnys0vaqt5OYt28XglWlNr3YvGwwuwnLZoFUUpkcXiLFNr65YNtgbvCpdcPqCV17tfpScZ7DTDJoNqMqc"
    encoded .= "U115ZLGLF46NvJXn75L5Cvcx0spzg8W2AZ4L471NR8pXH8BXf/tM2Vt9+9RYlZbzxgtv9bFf/4/qHvay01pin7Uay3r0wzPhlTZns/bbR2ABAPTckA8XvBpZ"
    encoded .= "M2gEr1R7NXPwqmd0HjWy3SB4ZSObXm1eNlj23ns0vRr3oOjBQ2hNLx2i6VXxEX2MvbpO06vDlw2uTjVotXRbe/AqataeqhnMtruSj5MN1ZXS6GptuzKRK/WK"
    encoded .= "JN2kh3irnLQy4XsqaUyS6iuRHdSl3rtDBO0iN4bMjVhXVy8rq6tnC++51O3VnboasOG13NbjfNS3Ty3VM/d81p3b+va6yfKl2W0hsAAADmivCF7Nr65sn+CV"
    encoded .= "6RNh7xO8suOWDV4veGXTlQ3ahE2v9rNXHl4ss/Yq3fSqpiSGNr2S7NXYplepskEheFXcFVLd37WDV14tefW4yLS9ZlCelXKIunKrBbs0dVVW6o2Rq/JFZbS3"
    encoded .= "ag5bCXPvdksrsRF67hvJVt3TrY3yC9g56/PM976sKq0SK/vGH3vzqb36iA0pF2x9OPn2Z774xGS9/MxqXWosn+UDQWABAGxstIaoq0Q3hLy6sqsFr5RvY7Xe"
    encoded .= "W732KgxedayG6nkag1eyvfLqdrYErzR7pQavbsheVaTIJmWDls4j7GGvyg9yq8VIXU2vLGhpU1gHj566RXs1qOmV1rI9KBuMml5FO2fissEB/dqvG7zaXV2Z"
    encoded .= "Wlu6mbqSqgXFyJVXblb1u6OP9FZtYSsPRnt9vaXSOWytoDG8Hfu4l89pRErqysy+/bln9bV844+++fKHH/v1j4zbDa2q68k7PCp+vF8d+URjfbFr+QgsAICH"
    encoded .= "aa92DF4pX3wptmTz4FUwJPX2NVHDKwlzZA85eGXblQ322Ku9ygaFHeWe2zlXanqVsld68GqEvfJglTdq2R46hfU+REObXo0vG+yyV51lgy392ruCV1ZIpa16"
    encoded .= "vYwWTNUMqp3aTQq1Zf2m1aNthYvlOHUlXdO9w1tZpvte0lt5ODzzjaWVJ16r6pD2L9my3qnJUu2ktp753peuWKLPPZccmZuZfd+P/uD9f378Nz5Su/c3maJF"
    encoded .= "Wpl40Xc9vJ6arLtjZxntzhBYAAA3qa4OGLxSWh4QvMqsw1GDVxbP/XelskFtzinboWwwtFedZYO1JQhPP36jTa/y9uoqTa+KfYhSZYPW2PQqJVlaDEuubHCi"
    encoded .= "4FVNXZUiaV3Bq3DHhvt2Q3WlNLoKlVzp4uaVO2S9E2TlEhTaKqV6z9vCVvUvkkZ/g6jJnmyj1OGiakMh1bBoX/NWl/ZK58Je/UF7j/ayLPIB+2NZLkzWSbv6"
    encoded .= "YnevqesHEVgAAL13iHjo4Y3qyqq59k51ZcOCV73qyoYFr4R0+2zBK5MCSJnxckvwStmqjrJBbzNelA1qZ/4NN70a1bLdhUux3PSqeBzEZYN99srrG7F306tN"
    encoded .= "+7WHVuWKwatOJ6gcHnOrq50iVyO8VXBjDbyVZwcS6Zt410Ai+qW3TGgojfCm0FLqX/j3fs+psfrSxXJyaaM1e9W3xaVNWaw7CbVypC6ffdYrW32ZypoyjIXA"
    encoded .= "AgDov+MeLng16hu/0F51qCtT0jGRa9B2/4GDV3b1ssH6d+7e8Det9srjA36AvdqqbNCmbHpVmRbN2ppetbdszzW9Ku/P0F5du+lVr2S5dtOrTfu1dwWvEs3a"
    encoded .= "o+BVo7qylppBj5xLVl15fQxT+D6jTV15JTBcqaLf2Fu5OuyIrvE5aTXAWIUTz3Z5IW/9Q23J3rFq5/zoz/xA09+9ovK73/h//WFVXZ2/48d/4w8vtmQZusu8"
    encoded .= "ILb6364yXlr6DiIEFgDA7PaK4FVFAskeTZAyUwSvrLmVRH0mpcwKjFNXNiR4ZVOXDVotEaiWDe5gr6ppA30qrsH2anzL9iZ7NVnL9pZp4K7X9OrGyganC14N"
    encoded .= "qxnsV1e22oxuKnVVjWemIldZb+XRhTo5eBDu2rmwtnrXM2sIO7dugjhu9Za331xUNb3Xz56812/e81lvuLBXn/iNP9RbNBQc1NKx20//sVTfZ5DbQmABABxd"
    encoded .= "Xdmg4FW7urKrtVoIZ7O/teCV+iEoHmeO4JUJ3wgfv2xwYPDKNm7Zvn3TqxZ7JbapEu2VVxIMO9irUS3bLRMOqpgNQbLYXE2vBpQNPtDgVa1mMOzUHibatlJX"
    encoded .= "Xr/Zl69ZSrVgYSrFGbxVcMuN5uftlVaeGz7I49aO+QL1esaRQ+wf/Znvv+5o/z33fNYn7s0u+Inf/MOTNV2aN3JAm/Za06rF25aJwAIAuEl7Nb5m0LYNXuV6"
    encoded .= "LtxE8MoF9bV12eCuwaucRRKCV7Zr2WAmDzVL2WC1f4p2avQ0vYquSLXH9jFNr4oayQV55eFpO85ebdz0Kmmv+ssGbZamV7Jk6bJXVwleDawZHNvuymtH5Xbq"
    encoded .= "SjgxWyNXHtyDglveKG/VFrYKO8BnvuLy5rFKXlcJMm1IQCv7uvcI3uo3/+kfnfz7VS9ZedHnv5xwVdGbvuHN999aGfJ0pazk3bh46k+XR6vjzb4MgQUAcEPq"
    encoded .= "ylIz5dkBg1dD1JURvLKrB69su7LBruCVaV9HN5YNhk9CR2t6NZu96m7Z7sG/iws7RMv2kU2vpkkJjSob1KcLTNmrnNEbvEvH1Ay6B4OMXdVVX7VgT+TKpfFY"
    encoded .= "g7dqmJFj/ehKmaCxxioaMomliom3bG6t1e6Pzo1VxV5lvFVp+ZX1OftVecWEgd6INu05FXV50C7FBcYTJSKwAAAObK+GB6+kDLoyhtgteJXxaMIqbBm8cvED"
    encoded .= "ny54FY/mhQ979+CVKT2aRja9isvUZmh6ZfXCtSs1vbqRlu05e+XC3qvbq6hnUD0iZAPaM9m1m17tUjaYCV4lygYns4HWNsng+nygs6orD/KxqchVUOY90FtV"
    encoded .= "7L4srbJzBuoDtkyCKjtMHa21/IkMelPZKH1UWvyrXnxqr77SnPy64/XvedP9gsFP/ubjNXn32tq+52e+/333HNaS3mVXaNN+skwv/nJky30EFgDANezV8YJX"
    encoded .= "gr1S+hpsXDNoUXOL1OhswuBV2l6FjmrCskFX9/kRygYt9pfjml512avBTa/KkYKHbK82btleDpRN3PRKLnDL2as5gleqDWzSeeEhka/ELOUiN1ZXShmvadWC"
    encoded .= "rlzke7yVjSgGb/JW3jjUU+79yYI/T/24xYtIX62+56ffVF/4b/7CR8Xdvbzyxee//eOvxBtU1UGvf8/56t3ZKzN73z9dN1nvvpfJet+5dxvQpn2pLWlgm/Yl"
    encoded .= "VFoILACAoymsoerKCF4l1JXtErwKp43M1AW0qCvbMHhlPWWD9UcZ+ZHgavZqZNmgRTUfibLB8fbKXT2/omfemr0Sp6tvadneYK/kCQc9vD5eu2W714/DvZpe"
    encoded .= "jSgbXDlw9J7rK/aqfA7cdvCq3qm9WNLrw9RVx8loYbWgGLny0jWp21u5MkWJ+p3HMGnl2m0yq6s6ElVuQzI4JXv1vl/4qLaWbmbLK7/7wlv9ibyNS+Ulr3/3"
    encoded .= "hb1630fXV/ifftQKgaxHP7ynsQa0aa+N55dK/62l+QPXdxoCCwDgoFJrc3uVUleW7IiwXfBKE3ItwSvLVG1uFLwaba+OGLyy1rJBT3zizWWDtmPTqwZ7pe6T"
    encoded .= "MU2vJrBXhTXZpmV75bMo2CsvhdW8eMlRI0Ipe3X0plfT9Gsf1fFqVB2l9bW7yk4yGPah201dVasFh0WufMyVPCOtLJ6PUZRWYpRcN1ZJ3+D6SKllrPxooe/+"
    encoded .= "6TdeeKuPZVf4zF7dU1edjsZe/+43nqqrj62eZ/fX5bF3W1ZM1oXGalyr2HAV0lJeF1KiOWs7nBBYAAAPXF3ZFYJXSk9RglcD1VVor2YJXunHgO9YNtjU9MqV"
    encoded .= "J6q+Z57BTa967JXHO9mlA2OkvVJbtkfPzImywfIHsG6vOiYcnLtl+4CmV1cvG5TCaHsEr5I1g5bSeaa0u2pRV1bzyNupK7FasNFbRbe8sd4qkFapgY3nJwBs"
    encoded .= "6U8UDnY6ZFBpgZfe6lRdJei2V5a0V9rm++PNudzSO7Elm6wGhbSISit6Cljy8gyBBQBwMHvVMlPe+vAoHuNMFbzKeLQuexXKJBfc4WGDV2PslZs3vXX9qSQ4"
    encoded .= "yI5XNmjBROhVx+fq48ROLdtT9kpv2W5CpCiyV9UJB104Nydo2V7u6iU3F5+7ZXtnmduwskG3WulspWzQq5bhMMGr46mrIBTt4UilELnSLHztOu1hMZ9ydxss"
    encoded .= "rTzhy9JjQtfXKu1N9EVVI1eJBS+v/K7LHz7zx18dlQx63bu/7/4/P/W+j7Ut9/2nW/eue5v/yGSdvOBcCy3LuM/o/A2knlbFrlgz5q8QWAAA+dvEVMGrtLoy"
    encoded .= "vT9C2l7tVTM4ffAqp8+yUsuEz3v3fu2mBa9UoxTbq53KBpVzI55k8dAt202IFFXlTpu9qnySU7Vsz9grD3SjYK82aNk+oulV3bZsVTaY6ALmF5vcFLwa2Ky9"
    encoded .= "HryS1JVVVKZvra72iFzVL2J1b6WMu4QvHureKlcOb8lav/g7sFx5fs4cNWuvd//0912oq4+ro7vTl3z7Fd914a3GcOatntirj+e3eyn5rHedKry7f77/Fz62"
    encoded .= "fotNpqCWZrGltmmfU14hsAAA8urKbi14NaZmULBXTREwE5529dW4/Bw3KRtsVVc2XfBKPgzcG0fVlZPD059yzV4NLRu0fNMrE5vz7tGyPWOvXGtQLLdsF+1V"
    encoded .= "74SDmZbtjfaq1iBM7y9ekiHplu22ZVxo5VTZoWww0HnlE2C24NU4dWVhp/bh6qrLHVu1tYE3R64291YjpJWcz82ODotj081dVW1T3v1TF97qFz/+6IVtJYvn"
    encoded .= "9uoLXx1lVF73ru+78FYDnhAuHNbH3/XTK5rsXT/9xvevhtGSKSjXyvsW5T084cYQWAAAB5NYm6orS/TRJHiVHPkJI27VoPUJtu2CVyWL0GyvRpQNeurwm6Zs"
    encoded .= "cJS98vpucelgZ8LB/e1VmFbb1F7t17J9+6ZX1ygbLO7MWhHlgOBVZ7P23ppB98OoK7FnX3eLq528Vae08obvH7NFAPLfeoMkulRX73+irtpc2bdf8aKznzzz"
    encoded .= "hT8dVjP4rjec2Kv3f2LtE1iGqJz3/8LH73mr7zt1WB+XjJFXpJRQPyjtNV/qP5jPZyGwAACmsFdDg1e7qSs7YvDKtiobTEw21GSvBgSvgoNhirLBscErG9f0"
    encoded .= "KlE2aD1Nr65grzw8nMdOODjOXvVNOCjYqxuecFAvdhve9Go1KNTTr33tpN4/eNXTrH2gurKKDdxDXXn1ciFduvsiVw3eKhoShN0ukwM5pW+7bqzyuqopE3X2"
    encoded .= "N+/6qZV40ft/8RO6qArt1TNf+NNGB1bgtaf26tPv/4SeRq+aotjxnAWy7v77/b/wcf1timslOatFPkhOfrDMV0qIwAIASN+2x6ormzF4deVm7aZOUC3JramD"
    encoded .= "V2VhQtlgt73y2tbOaa/iXsGbTDgo2Ktcy3bbbsLBqe1VV8v2vSYczLVqKtsrvenVFmWDzf3avXpabBG8yqkrSyTRwk7ts6iryiyRg4qd16ott/NWQ6RV9t/a"
    encoded .= "Gw3p4R7e4971U29Y81bDBtjPW1NXnVzaq3HPBi5Ip+UDT1JX77wwWR/4hY+XnVO+U7va02pp/oAQWAAAB7VXQ6reEuoqGo10qavUOExYi6beW2kv5Kkg/e0F"
    encoded .= "r+KqwW0KHwaWDfbZK098akLZYL+92q/pVdpe9eQXBtqrvgkHE/aqmv7YY8LB7pbtY+zV4KZXq7u3p2yw7D9c8SyXwavVXTE0eNXc/8t2rBkMT71+deWVI7J6"
    encoded .= "jRaqBXXbbnpctH7TFL4ISXurMIXeOmwT7wPqKDf3V7K9yvmzb73ihVtok9e+6/WXP/z0+z+pvcXA6QH9bnkf+IVPvPOnT/bhOwsaS//6fKkrr0Sb9uk7YCGw"
    encoded .= "AAAGeq25g1fKjHPjawZb7ZWybzLm6NrBKxOzOFmLdIWyQRcLHW6ibNC2bHrVb69c/Oxuz15FnXdCexU8Qo+2V2s7J5pw0EyxVxu1bB9fNrgqXAongL4z+4JX"
    encoded .= "67vxOsGr/pZqrerK8jMMtqkr4XrVEbnayluFcwnmbk7a0FEd+mQtT2sia81bPbFXn/TGrNg9dfXy++rKnvfFP0us5ZKwV59+/yf7h/pdquvJ8j7wi59458X+"
    encoded .= "vEtmfeAXPpHVSV53Umct35fUJk+ntBBYAAAD1JUdPniV9GjVNe1TV7ZL8KpXXV0/eGW2TdmgJ/Z8T9ngVvaqOht6Q9mgqb3h9mvZvpW9UicctDAMtoW9EiqY"
    encoded .= "vPScm5pwMC7L6rRXzXPk2RbT5B2q6ZW+J/V+7fsHr3pqBuuzAVgy1re9uvLyepoJ6ioucLaw5nqMt8pMkJKWVuJ4MaWeOhJZa5/Ou37yxAR94L2fFEdCurcy"
    encoded .= "s+d98Wv6Wte38DXvfN3ZTz7zgU8+XdvxTsajRZ7//gOnybX7PuudP/2GJw4r3dBKut376RKW+uKmKyJ8hidRAIBOe+Utk+UpyR0/+X8mvPP6V3m1oijdXrmF"
    encoded .= "pVf99sotThXlgldT2isfUDbowZFT3gxf2+nx+3rQX9sTR6D32Ct/0PbKM/bKx9srn8te+cly5rBXvo298jV7tXo++2r3qBOv0mavPLRXfnZvWdsjF02vSvbK"
    encoded .= "T/90rWzQV+8LZ78/W2fRXrmvNQ67dFN+9sonp4ivXRvdvXo589qt2YvBK79YEV9Zfz9/yXmWzVfWt3DvcF8dyfjJUXpxsPnaHcEfseLa/PJIOjv7vDig8rvl"
    encoded .= "ri3WT/7r6f7xi5/6xZ48X5Q/+cjdLzf3/G7l5/vBi/fMp1vgwqDRT9fH3ZSBpt/b8Pv/O/9ByV5VViP835m9ev4Xv/b8L37NM4uosGavPnXy1y78z7S9qG58"
    encoded .= "7c1WfNZPv6G6tdldUl3C/UPNe5e7AySwAADa1ZVNHbxSwjcEr8In9vrzc0ZdmdKvPex28SDKBk2bO2mGplc14aDsE29v2W7Dmsgk7JXw0av2qhKky4ZBhrRs"
    encoded .= "t0w6xloCMl326nJ52oSDzS3b5ZK3jZpebVQ2uN9Ug544tEbWDK5HFMumeN0Qeu0uPSJ1tUnkqnSHrM5LmOv+UBmetSatXHnf1L2+dptKDIzM3vmT5w2kPvDe"
    encoded .= "T6WcxupLv/nyF5zZq4GD9TN79ZkPfKp71L+2EYv0I/mt3Mw++Iuf/JGferrD7zJZH/zFT9ytQnXmw86eVpdn6jJnRywEFgDAIHVlJgSvMupKfGfdXjU1azfL"
    encoded .= "Pf6nujnIMk1p3BCqsBmCV/kVqDwBNagrG1s26NmPvj14VXkC2yx4ZUpflerO6LBXHi6yaq9cPqM9fp5bX6Qrl5ZB9mrzCQf3sFebTji4/vCu26tEr3G5ZfuQ"
    encoded .= "pldDygb10ku1fPKiQX9zx6uemsHOTu3bqqtkoytRXZWvltHIqMNbeW7UM7iTpgnfESYGm4rIeudPvm7NW7UosLq6MrPnf/HrA1M+r3nna0/t1ae3aupUbdPe"
    encoded .= "LJI++IuP0233TdaP/NQb7n7+9D0KMw8uI62Wz5i/QmABAIy4cw0JXnnOdWSF0fjg1YzN2m2C4FWTvZo0eCUKK/Eg7CsbtJ3t1XXLBq06G3pz06sj2KuGCQf3"
    encoded .= "t1ce7aJ97JWWG6rbq3LDps1atgd9mmqzDVp1Bsn0bINevchOH7zqnMVysLoqXhP+3F/6i//x3/378rXJw/ttMnK1gbdSxjv1G7oyxKsPIprGRw3TGp7Zqzt1"
    encoded .= "1bCoC3v1nafeajBn9uqzH/h0b3v5uhrSl73U33RZNVmnDuv1dw6r8FEsJ79b6u90gE7tCCwAgM3UlR0reJVfmUZ7tU/wShGJxw9emVpJ6tqbtASvOu2Vhx/2"
    encoded .= "sLLB6N0ebsv2+nE92l6FrdZN6Fe1j73yYI8LpkAXDR32atSEg6mmV6bZK69KBdFeFeNCUgZtZNmg3q9dD14NaNbef0SZHugboa4e2atH//cjv/Yf4vumHrkS"
    encoded .= "Zob1wd5qAmklLCbRHl6wVx9876ddLlJU7cOzX0+PGiPD9OpTdfXIXo0e9ru0KuVFLMXXri/50mHd/Vz+5JdQXJ0LsCP4LAQWAECbvRqsrmyK4NUQdWW3FLxK"
    encoded .= "GbThwauHUzZoY5teVU+azeyVVuGYano1zl7VXW/pMdWqInMCe+XCEaN3aOq3V8GscBnXMGrCwSA61GOv+ppe6XsyKhtcP626ygavF7zqnsIyUTNYPr9GqKs7"
    encoded .= "e/WIN//4X3jisHrVlRa58uCONMBbdUorF/4dDyP1HpqVm86P/ORrVwTKL326u4Ls8TZ842XfkRwbJ3j1O1/z1Ft98DPxEHLZTtPUYlbx6PlCN33wFz/1xF69"
    encoded .= "7r7JKjgsZbC5lLa7dKudUGUhsAAAGm5K3tuEwGoja23kNFZdKfaqw6Pl1mjD4JWp35eGBi0a4XqrPqs/novvXisbjKcDH102mIx61TVR+EThqcO7o+nV2v4Y"
    encoded .= "2bL9mPYq6G5TnPZhC3sVPF1vbK8k11DLDQ21V8Natp+v8SB7JTW9Wg9eWa7p1bDg1epO2C141Vcz6JX7Q1ZdrW+Lm5l/5Nf+w5t//C/cd1iP/uMjv/Y/em1c"
    encoded .= "4aWfCZGrVm/lmbtMdF1MNUxP/HXiVi7c35/814/8F68991ZJTVNalfve6hHf8ew3NhqlP1VXiQG9R4ZL/UWn21r/aO+924d+8VPvOHdYn2pasYtDeFma1xuB"
    encoded .= "BQBwCHt1uODVFDWD0cgyNXx7GMErm61s0Bs+/chezVU2mLNXW7dsH2Cv4qZXu9orpWX7Ne3V2iN91TX0J2VG26tNJhwc0bLdqwdJl72KdmCt81dLv/ZyyzDL"
    encoded .= "Ba9GH0797a68dgp7Ul3d/egudfXmH//z90zWn/+DX///aWOnWF1VvxuLL/6J+0u0CnrHJaVthHCh1kZT1b8r2Ct5VFrmzF5toa5e/SOv2XrQf/6LwPYs495v"
    encoded .= "Ofvxh977qXf85H2H9boPPXVYfvHH8pqcXU4Wm78fli/LkVp2AcBD5nOf/pKZveSlL9r5fX/8h/6WPH5w4e7eqK7s2MErF1+Yy9t7djVsbPBKWaesQorWYKOy"
    encoded .= "QTV4peqkHcsGbf6mVy32yuWDx12tl3TtqHALk2brO24je1WuXTuyvQoaeEX2aqX0rH/CwfOV3bple1vTK2EnbFU2qJejjgpe9RxLifkrt1BXl5vzg/cclpnd"
    encoded .= "OawNIlcbXPYL18ItpZXui7SvCMve6om9+kybqzpbmW+87Dwi8x3PfnOAPrrH9/7Iq08eED742Y5h/ggZEnd6H6JclnecNin70C9+KruKS3qjlr/1/3w1AgsA"
    encoded .= "4HACa6rgVRxO3y54ZckWoRsFr8LvQxPmiODVJvYq+Y6Fz1V4wLDZm14FOi+YcLD+IRamp+ybcNCUutEN7VUtapGxV2UFFtmraG64jexV1KLIy5/6zvaq0rJd"
    encoded .= "r3rbs+lVnD4Tp1zcO3jV2f4/dHlWTLGNVVd3W/CDP/af3H/FH/76/9SlrtRSwT5vpYatwq9QtDFARlfJpslP7dVJcOlDvyQW30lvVbJXQyrRzrxVt7raWHUt"
    encoded .= "yu/TKuYdaw3LPvTeT+WXtIgr+7f+yfcisAAAjiWw/qubC16FDQBuLHgVKr/+Zqv7Ba/sVssGm5te5eyVJ4/ROIok2CtX98YB7FX5EbjXXnl9Z67tSbdCgLI4"
    encoded .= "BVtgr8IddSx75SYomHETDra1bA8mXiw0vRpeNrhFv3Y9eDWsZlAN8anqymo+VFRXp78/c1j3NJaHgikZuRrlreTg81bSyjPfHAbLq9qrpGW6WKuvv/TEXn3n"
    encoded .= "c99sX9ylvXrHiUb53Ic+Zxa3cNqXpfP3l69bZJP1ofd++ukfLcPWf5lPYD3DIzEAQMct1V2aLC+0Vy781LWOV4mpBj2zTS6s8Poo04M949que7yFo+yVN9or"
    encoded .= "T9sr77NX58eP14+RxFt7q73yYnyqp+lV2l55+ZCfw14FO8S9aq+8bq/8AdkrL9grP5y98gZ75Ve1V16zV95qr9b2g2v2yjV75bq98rDt17q9cvOLssF7x6R7"
    encoded .= "+dZ89qe+upGCvfKLyNiTj/l0j6ycv762Vve39mJBvjIkORsu+Plfrgwn/DJ19QM/9kOPdpevHvYnq+xrt0Qv3hlP1tsLNy/300/rdCN87S99dWmPF/R4q72c"
    encoded .= "un3ywtocJvf/d/J+a1vq5a07+d2Fvfrsyt967X+n6/X0x9946fMv7NW3gmVFax7bKzvdl+H/mt46+cBQXb76zn7v2C6u/W+999MFn3W54W3r3yA1d3ksI4EF"
    encoded .= "AEfhagms/+S/kh5uI/excfAqX8Aob1NjzaAdI3ilvE5fp+IDf30nzFU26A0HgKKubFDZoNU6Sqllg/32anTTKxsy4aAFhX5mlU43aXtVq9Yp2ysXTgKPThKP"
    encoded .= "CjWntFcW2qt6XmZ/e1XapWrbppVp/tb7itcVXumcqjS9Gl42OHXwSq0ZLM9caWIVatUGlo+rlR/9wI/90P1//tFv/MfCDagzcjXq+4n6Haytar5hiCN2fF/5"
    encoded .= "1zv+i5P6uw/98me15cTv+PWXPu/sJ9/53LcGjsPP7NXn7+zVWOL41LL5Wy7pP3/7WkXhb73309WpFHNv87//J69CYAEAHF1g5dSVie2kks/woztedXi04hi6"
    encoded .= "aU2KLmCEvWrteGUtwav4E3Fve/e68smPpLcvG5zKXgnvsrO9cn0nVCYcvLa98qKHOZi98mivz2avgvI3ccLBHnslTDh4raZXatngxdqJ9krv1653vKoUkFpf"
    encoded .= "zWC2U3vDCRurq7sF/8CP/rnLS9wf/cZHkuoq9eWEK9/cxCOffm8lze+cNVYrK/6Ov7HSgfvMXnlrzqZBXaVmVHzVO87Vyec/9PkuC7WN26q8aOl5s8wfv/0n"
    encoded .= "X3PmsOL1kUoVEVgAAMcWWMLXaDuqq5YUmGyvNgheeWrbSo+q7QOj7YNXukLS7ZXLn8yW9qp+7OzW9KraEircXbs0vZplwkHs1ez2yr3kEK5gr9YtzO72KtH5"
    encoded .= "a8umV8XP4mJFXD6QtgxeNc4zmOnUPlpdna3c9//om++/6KO/8QelG5WgroRrb9tdzxXXUx1gdHcXrVwlVjmzVx/65c/ZuKKwNXv17YEVZ3l7tbmjav2LpfsV"
    encoded .= "UsP3M4dV0VgrSy+3dJ9NYNEDCwBAx30ie5Vrv9Xd8ar+Nq51vKq/JOx45V3Bq/WeICPtlUttyJ6sgEs7IdAx5/1C8mWDrrxvpU2HVzuUNzS98uPbK8deDbJX"
    encoded .= "3m2vvM9e+YO3V162V76ib3zt9D5v2Z6xV67aq/PL78rm37v2ns+3uDJR4+XmX/T8KpYN+mVvKanjla+uc6Xj1eWtdeWe8LR31NrKX7SQWmt3ddln6mylfS3O"
    encoded .= "5it3dLfV3XuXunrEm370B1fX1lfvt/60O1O5xVWtq5XbZZ+si7dyv9iNZ2tY6H1VaEVU7jtVG2A86Yl13oNq9S/O7NVv/fLnkg2fik2j3PzMXr3guW+/YEt7"
    encoded .= "9fkPfX5Le2UtXboS3bTil0ZvvNaB7ILfeu9nLpTWa9X1O+26dnqETfYwRgILAI7CVRNY6eCVid+0tagrGxS8ciGtrnwTuEnwKjXrzkbBK7PqJOapdTDLBq/s"
    encoded .= "SmWD4tE4W9ngDPYqN+HgfvaqatOCJMJ17VV0TY3tVf1TCO2VDbJXcamaZq+Kk7td1s2VzqxLe+XFUy3OEK15QC83TBInHBSaXq3suj2bXlXKBqXWaWPsp1Az"
    encoded .= "WMugmdLuKjpPVy4waurq8hWn3so++pt/aEMiV+VvZ9yCG4i33eakby/l8ZUkEE4+l7f/jfNp437rlz+nj3zC333tpSchmBd86dupNQzU1dtfefaTz//WH5/8"
    encoded .= "ewmXHviNDfTHMujNlvY3vmd1LsoJP9P+jov9l//klQgsAIBjCaz/w6bqSniubldXlsmxqx4toa6atJF3VC9GcmOzfu1axytTG/nvVTbY0q/dik3EN7JXXn9K"
    encoded .= "EHfXUHvlhb/3xN7AXnXZq/CReKy98ujS5+mORRPaq8qEg9Y64aCtTji4act2tWP9xmWDlarJs7XeoONVS81golP7cHV19+M3vefEYX3sN/9wkLra3ltJN/h4"
    encoded .= "qKB8X1of6d23V6feShhNCW/9te85s1ftMuHy3V55z1798Zm3Gm2WRkmtJfv7jZXWoz9620++WnZYwXv9l/+PuQTW83kkBgDI3l8H2qvRwStBXY0JXrlnNi4x"
    encoded .= "mY43VC9Kg8z24FX8JtcJXllbM46+2QYje+X6sZcIXllX2aDwMZVnVBthr1zVZb6+B7BXU9urJvtwHXvltUzpYHvl616ow17t1fQqCF6ZNNtgpV/7HsGr2jyD"
    encoded .= "LZ3aw0kGvXJ3EtXVo5999Df/8E3v+YG7f7/xyX9/7H1/dFVvVb9x+i7SShng3RMWv/x5eaCljlq/9j3nP6/Yq57CszHqSlmPRV/f5i3180W4ZTq1e4vScvvw"
    encoded .= "L332bffmnXz7T77mw+/9zJLbWZPmnBBYAADD7ooEr2R1ZSOCV8oUglv3a3fxQ3EteGWjywab7NU2ZYPF92iwVyPLBgu7SG56lbZXCYsn26t8NqH2gOfaJWiI"
    encoded .= "vQofjLFXO9irmohZPVp85QRzxcLI9qq/ZXsud7ZZ2aBedjoqeJWoGVw7SfdSV+VU8JPUlb/xPd//1GS9+/s//r4/6lZXnrtF1xbnjeO64mUqPz65+M3b/8ar"
    encoded .= "kvf1hGW6b68eeSvtj9W3eOXbXzFIf2XMi+vL8P63i27+yyItTFVaZw7rbT/5GjP78Hs/e/YnS/dnh8ACALh9eyUNcTwaKKXUFcGrBnk0JHhlbWWDdTPTVMF3"
    encoded .= "pLLBnexVuIu0lu2aGrNU2WDtGW9ne+WFBvDYq23sVV1A3Iy96p9wsL/pVetki81lg/XpAnuCV+WaQVODV9lo5Hh1dfaTj73vj9747qcO6/ve/f0ff99Ho5us"
    encoded .= "S8Mt2VtZZY7H3JAguGFow5L1H597K7Pf+mef91xgS12tF35pvNo4VVf2x7/1heFD9Bbh5bqq8l6PVjoJl0VbVjE59eFf+uxje3Vnsu7Om+X+D5bOVUdgAQDc"
    encoded .= "rLqyKwSvXBgBPfTgleX6tV8teGUHLxuUjn+h6ZWyx45sr1zuup+YcPDh2SuvX+gObq/U4Mz17JXYsr1ir/pbtlc+CLHpVVvDL5PLBpuDV3Kz9r6awUHnppXk"
    encoded .= "slV1/Mff99Hve/eb7jmsN338fR9tj1wFg6stvNUoaVW8Hb39r5/Yqw//s89bcbZEcUB5/rd/9j2bDKbPvNWdurpG7Mcjs7UUX7g0LFYPiJ0ehotomlZ81iOT"
    encoded .= "dT+QdWrKzv9k0vAVAgsAoP8O53rE+yrBK+9Lga3fQtvs1a7Bq9RqbBG8arVXcqgoba9am3R46zRMq1NajbBXcsv2bNMr01u2H85eCQ97KwbApSvUoexV3j5c"
    encoded .= "1175+mLmtVeNEw6226v+lu1tTa/ayga9dExmOtbblsErj65zlVLKbnW1ttxLh2Vmn3j/x0rXZ6/dJTKlgu3eKpw8UJFW8eDoTF2Z2Yf/2R9n/E/8FemZunoS"
    encoded .= "vxJFTW089oq3vfz+P7/w4S+uHiitQaBh+SHhK+fl/I3H1QDWBhdLzTQthbf78C99LlijZUVuIbAAAG7EXm0WvEqrK9sweDVEXVm5YeoIdWVRCYEuj7xjHeIx"
    encoded .= "cn5S7UOXDdruTa8kexU3vQrXdtsJB/e1V17c4lH2KoxB3Yq9sodmr7w8a13SXlUmHLSgalJr2S63qy82vRK1ndWDV1YsG7xK8Mor55RUM+geXn+EC248+8TH"
    encoded .= "3/ex73v3G+//5A3veuMn3v/x2CsFwypPDcH6vFVSWtWW4mb2tr/+yjV71XCzjr2Vmb3wy4HySgV2Vu3VgOU+9S2e/YNRTwf3Dp9im3atXlHst35W/7dUdlsh"
    encoded .= "RbYUV2Rp/gwQWAAAk6krmz14JQSVxgSvtN5bwQpmqheFUdkWwSvdH9k8wSvJXlWPW6Fs0IY1vXKlzHGHlu3Yq8JR7PWFFp4ej2OvrNte+UT2ai2X02Cv1lY4"
    encoded .= "Z6+83EJ8rL0SW7bv2fSqrWzQrVbxO2iqwXTNYNjuait1dffrT7zvY+b2hne98Z7D+r47h5VUVzlvFQ1CoiL6cOwR3Y0v3/3MXp2qK+XLvNq2/tlLllN1pS2w"
    encoded .= "SV0F9mrYmL3uhdrnH1TX43QeQl+Ud8oorfsf0VL8k4LVcklmIbAAAA5sszLqSrIPxw9emdKyofLcndrflae8zFhGF0SJ4JVJps82CF7Z2LLB9qZXfWWDCXt1"
    encoded .= "jaZXtd3i60tI7Ioee9UyM1efvfL4NDmWvfKj26tKv/DJ7VXlE8m3bB9gr/YsG7xa8CpVMzhKXVl5qgmt15594v0ff8O7vu++wzKzT77/E/Ld2Csnf+buX28K"
    encoded .= "Kk/3nB94rAWvviDe8pVfnNmrF3252WH4mr162T1v9exmmmRJrlf4RwPmHyyPkZa6tSqYpvJbVztbRdvmVkmOIbAAAA7orqLyJcs+t+v2qktdGcGrVkG0d/DK"
    encoded .= "NiwbFO3VwLJBG9T0SrZXctOrQ9krr+5k2V5FQbCD2ivDXjXbKy8fhFezV30TDlYODy9dKJpatoszLZocOqtse8peVU+Q3ppBj775Wes8NkZdPX3No9SVm73+"
    encoded .= "icl6/bve8Og/PvmBTwyJXA30VhlpFXekWrVX2a8bK6/408BejTFNj9TVluGepvpBTWwt0nstubU9j0CJMx0Ksul8yVJnKx/9iSOwAACuJK8OH7wa36zdbjp4"
    encoded .= "JYwmNy0bbApelQ+ojcsGvfo2m5UNWlPTKyuXElaOHM8sf91eeWavx/NzxfZKn5/r+vYqrFEqPPA79qpir9YFhAc7U7RXXvq0ZYmzl72qNL0q2qsxTa9yZYNx"
    encoded .= "v/bNglcu1NX6juoquDe4PQle3dkrM3v9O9/wqQ98MhixuCVSurG3cmnc5Za5fay87G1//XzCvt/+51+wfDPW0ivO1JWZvejLzwwUSC+/l72aTIpEBYfVhFJp"
    encoded .= "mUuz1To7IpYW2bSEqm2lTdikYSsEFgBA490tOVNeQl3ZLMErxQntE7xyl3edHTV4ZVOWDbp7/k0Lh/w2ZYOz2avyrIiqvVrNIVVnQsReHdheefWoukl7VXQx"
    encoded .= "rjZ+aphwUGzZXm16JdkrsVe9ru2stWywJ3iVnWcwnGRwc3V1/9+f/MAnX//O19/97HXvfP2nPvDJcitCz406PBHRNYv2U0Janfy+ZK+addXZz/70Jd9usFfK"
    encoded .= "Jrz8bS89++kXP/zclgpruIWp7Lxa+Km+zxd9baud2uXHkItYl18uaeppBxFYAAA9t6+pglfKhDcubqLL6soag1fJCJgw6mvvPTFr8Ep/93zZYCDFcuLwCvaq"
    encoded .= "cvjPa69GNr3CXt26vTLsVWWn7Wmvitd4L2y1KU2vesoGVwoYC+fu4OBVZJ1KV5vyGVy81FTvCrXk2ac+8MnXnTqsR//xqQ98qjFydR1vtX4zeetfe8Wpuvpi"
    encoded .= "eENPNbs4s1eX6kpJ5q/y8ree2Ksv/vZz+WVkbdWVJh+Mwk/yqGzROnHVOrULx969WJevLmN2mYXAAgBoEll96sr2CF4l1ZU1B6/C0L3dXvDKMtH9h1M22Gev"
    encoded .= "KkdaS9Mr655wcDWcgL3a116pz8yD7ZWNtVem2CsP7ZVhr2z0hIPXanpVKRts7tfeE7yqfPptNYN7qKs77lJXr3vn6+6ZrNd9+oOfbvNW4g3UBWllJqTkCzu6"
    encoded .= "YK+SwwxNXZnZi77yPB8kmNbt1QbD7g5D5ct4vbV2PCz6os52fzlzdSKesr5pLdblZ2YrfTghsAAAjqSuBPUghJzK70Xw6jaDV3b8ssFQtCQOuR3KBnP2Kt2y"
    encoded .= "PbE3hturcoyjcgJgryr2ym3PvleqvXLs1ZT2aqeyQa+fTQl7JQevtlZXle5Soro6+9enPvCp+w7rtT/y2lOHtfrF087eSqkwdzN76197ed1eyV9VruzdP33x"
    encoded .= "t+7+8V1fed7AEfOZujKzL/72l5QW9R0s2laf/0V2NP7kT5Nua8VKiUs4O7OWlY3o7Wy1Nmeh580bAgsA4Ghya7fgVfBukwSvrLn3VmJkuae92jZ4pb+7yzuv"
    encoded .= "u2zQs8fhwygbxF5hr+ayVxbaKzuEvapUz3Xaq7Et25NNr3z9o9TKBvcLXqVqBq3YwH51O6pXGB+pru4Olk9/8NOv/ZHX3ndYj/7jMx/8TKe6qnqrTEK8Gl8+"
    encoded .= "81b37ZU6xpNbDCTVlVe91fec/eTZ3/6SOBAcMxJPCa+OyQNd+OOoEtAvXrfkN3O5/JwvlpcKZ13IsEknIURgAQB03TMPF7xSdNrhg1em9qSwjYJXwX6YoGyw"
    encoded .= "Gr3as2wQezXOXtnE9sq2slf2sO2Vh/Zq/Vp/GHtVyB95+TuAq9sroWzQUjMt2rB+7SODVy5cm4uN3jZSV3f/vEtd3TdZr/mR1zx2WPt5K0/855q9euKt3BPf"
    encoded .= "3wUq7av3sldZGVT63ctO7dWdupp38F778dJgtQrDjMXqrqsYsWrxWauf/bLUXq/LLAQWAMDDUlemd0DIqysbGbySV6bXXuWCV3adssENgleKEKsNhoKdN7Bf"
    encoded .= "e9JeedNRJze9slKWYTd7VbZsib3Rbq+8omyqWrrdXimPl7q98sheWaO9EqaNu9ygh2Wv/Dr2KuhBvq+9Wjl+ok22csv2PZte1coGz/dq+S4cd7yqifL+msFY"
    encoded .= "Xa29gyu3Bi/eEN3NPvPBz7zmR15z4rA+9Fn9jlnsgpj3Vsp3S2f26nf++bMeD8GUlPq6uvqurzy/0WPl7NVGMZ7trErpiFvyb+urq13aI0t7m/aicvKLHy9p"
    encoded .= "RTVdEAuBBQCwrb3aPnilqivrDV7to65stuBVk73ylkUqg+Prlg1aR9OrPnuVbtm+gb3y6EpQXkm3amuuyF65fFKPs1e+r73yze2Vb2qvrGqvDHt1LHslbnLF"
    encoded .= "XjWWDVpxpkVrLxvcJniVrRnMqCsrFgjHbul8T507rHe82sw++1hj+SbeSgtbhfZKHJqFo67LyNWlupIVhd/zVi+5/PWzv/Pl5sIzz+mhfNlgrwwr3KBynaJq"
    encoded .= "Maj1EFdvZ6tzZ3W5n5fppx1EYAEA7KSuLBm8smS0ZbLgVX5NBK2kzwZ9K8Er26xs0KvvLeikicsGrfC9fGYveb1EdLS9EucHfGj2yhrtlV3bXnnVXjn2qm6v"
    encoded .= "vHwueuFwEnvVVzfZCyLMlAkH21q2V7JLQ8oGvXpZ2yB45dHZbXKn9tHq6m7n3KWuHtkrM3v1k//47Ic+V77aiOqq7dudk3V+y1972Ym9+pVn698o6WOYr774"
    encoded .= "m5fqqms2ZrOXveUlK95qhGQaaqUSi/bMspb6YGNJrVZspnxFLt2fP7EpnOXr/zpd+LwmC4EFALCJvRqgrozgVdZexeoqNfIbE7wyygaTpixpr1z8WXU5D8Ne"
    encoded .= "ef0En8BeeaO98qq9ClVX3V7ZZvbqcqo70V4Z9mqYvdpywsG2plcblg0OCl4NqBncR12dLeiRrnr1O7737uevfsf3fvZDnwtvAeNujjVv9dRe5aRV8Tdn9uq7"
    encoded .= "74JXSoWA4K3M7Lnf+XJyQQ35rKVxYb3lfusL8mgxS2OPdsFn3T/oTtu0y9bpVGb5yludHdkTeiwEFgDAYHVlUwSvPBx83UbwKmPSEvLIvCH85eHo9wbKBu1o"
    encoded .= "Ta/CvRRWi4Rb/+DslR3NXnmfvfLN7FXl+b/48Xt512OvSju/wV5t1bJdbHq1dj4O1ab16Q4Szdr72l3tpa7uv+qzH/rcmcO6++/P/dbn1VtV2ludb+NK6urx"
    encoded .= "LzMTGgre6rG9+pPv6OlldGavnvudr3QIqfwYvP3vlm6xVVqBJTOYe5zx6khOXfzJeorqfsuujMwq564mnIoQgQUA0GevpOjQGHUlqbTg2XagumryaGl1ZQ86"
    encoded .= "eGVh1V88Yu4qG7SrNb0aYq+k6aU67FV9wsFd7JXHR8Vwe+V72Ss7tL2yQfbKy7vem+2V3YK9qnRPK9mr3SccbG961Vg2qAevUvZq7WQNawb3VVcuXAyfOqzP"
    encoded .= "v/odr7r8+fe+/VWf+60/Hu6tLq8Eb/mJM3v1nJT2qr+Tm5n9yXd/89xbtdiak3d86VteXLBXRxjCBz9rLpjztBi7fygvZyvR3qa9/OOTXyziwg9QQYjAAgDo"
    encoded .= "vTMOCV65sIi8umq0V0r66yjBq5y6UpVa+Jl54wocvWzQ6okZ0St5W9OrUfaq2p9rkL2KBCH2qn5MDbJX4aHiXr1S6p2z672HxtorU+zVerVdaW0frr3y8llX"
    encoded .= "a3ol2qumpld62eBUwSv3eOy0h7q62+9Pwlb2vW9/1anDeuXnnzisymXeU3mr09eu2asmaXVR6/on3/2NpL1aHyacGatN7dW1Az6+rK/Hsq3SOq/kOw9bLbn3"
    encoded .= "uphasNapa5HW7C6/Np/JQmABAAxQV3b94JVHz/fWH7xq92jCkKm9ZG+QvdKDVybMDSmsQNijtdleNQev7Mplg+32anDLds1eeXB8X91eGfYqPsvkvmhee35v"
    encoded .= "t1dRQ6u0vQq0lAXtw4s70K20UYezVyvyZaC9Gtr0aot61asHryJ1VZ0QtlVdlXyYP4pcfe/bX3n3o1c9+e/Pf/gLA72Vmb/lJ1569qPf/ZXn9JkKS6b6zFsV"
    encoded .= "7JXa+GrVXhW8lTbO2JUx9YErH/XSoHM0pbXWpt3X/kT1YTWTdf88Cpfs1/0sEVgAAAPtVbu6si2DV332akjwShgh7RW8skwmbkzwqi4YEvZqorLB3e2Vp48u"
    encoded .= "H9yy/XbslR/dXlndXllgr8JPsSihvG6UvdbivcdeFRKMXj48BXuVmPxOs1f1+rWbsFflrJnt2LK9a7bBQr/29RrSYLqAMHjVXjPo2l3ApVM0oa7O99eT1JW/"
    encoded .= "6u2veGqy3vaKO42VuDcVLv6r9kocKVTevZC6UooDJHv13O/8SfmTurp9alNnS9uCT46xJSWYSqtX7ji1rF4ilrQPi0zW6pInLh9EYAEAtNwZdwteuWsr1K2u"
    encoded .= "7BDBK9uobDDdr31k8MpGlw2WjxuPj8b1/8w0+JDslZf3bLLp1Vz2ysMHGOxV0l553V55YK88tFdetFdiMMqqVYdpexVNfmfrOaCN7ZWJ9sqxV6t/1d/0qjZj"
    encoded .= "4BZlg0LwymuXhxX7Zq01g5urq7PFfP7DX3jkrc401h9/+Iu1dYu+AzuzV7/7K1+q3w3FcdeFvfrOvLRyM3vpW7778hfP/e6fbCWqeuzTAMXiA5Z70aB9VW5F"
    encoded .= "C/Xiq9Z/c+6/ZB8WNrfyymIRWAAAx7VXhwteyR4tsDUErzaxV3MEr5rt1cimV9VjvuJmB9ursGvvvvbK5eekYfbKxtmraDWPYq/WH9bNhIf2fexVoYN44YBu"
    encoded .= "sVfaxHIl5Xd4e+XrR4Fi60baq6Flg175PDcIXs2srlbW6NJhmdkr3/byR//xxx9+Vh9CXKau7tkrK16BBC7LBl/8xF7Fg0a3l/7wd5de9KVH3qqldGxH7+FV"
    encoded .= "NbT0Lje9uJr/KfqgpfbWa23al8B/VUsW9Tbt3r8fEVgAAHOpK2ucLM+0GM1uwatYs+wVvHLhDa7er92VHfBAywb3t1e1g2oSeyUE0OazV95mr4L9Gf+Jaq+q"
    encoded .= "Z0v5SMtMO2iNQZiSTagJgsBeVU46cf47W48Cedm1JeyVS/bKt7BXlT2v2KvEHIvb2Kta2aAV003S8Ra1q7dk2WBH8EqpGfTCZafwZuPVVeGLkbO81Z29MrNX"
    encoded .= "vu1l93/1hd9+tnTTKaSu1i884sDvT77767K3Kt5XS/bqTl3taaZ8i7/2NY2zNDuupNUKtNJSWW4wuaBWD1iLbJ2fAYtmshBYAABHtlfXDl4pBWdDglcj1JVU"
    encoded .= "nvfgglcmdI9PqSsbWjYofPqHa3rVNOHgeHvl8kfnyvE1kb1y9bpXEV6SvSo/7pY0n6fslYdlUMNtQsVeuVngLwfZKy8cZrvaK2u2V/Fuv7692rLp1eiyQS/b"
    encoded .= "tKq6qvxp4RrorlyT3ePr3gB1Vfnu0B+lrs7U1SNe8daXmdkXfvu5s3f54ZK9ynmrs2btX6+pq+jbz8hb+UBhMZn58OIdeIlF1qJuotqgvfJXhYV6+IPCu0aR"
    encoded .= "rad7ZtIJBxFYAABb3JIPELyyeFI2Cx6x1Cf/YIM2Cl5tZK/04JVNXzZoY5pejSsb3M9eeeh5b9peufa2o+yVN9grr23+OHtlnfYq10LbxCyMF1NmZXvlW9gr"
    encoded .= "381eFVuYt9or381erRUhrtgrydZV7dUWTa9SZYOdwavtagZFdVW9Tai34fMV+cJvP3tfWp1qrMe66ou//SUz++Gf+J4Te/WrX5IHDMXb1Vcu7ZVWblitFvxq"
    encoded .= "j27y4S8U3dHIYb0X3nAR134pbuYiyKz4ry5veUtJZsmxrNVz8mlWbJndYyGwAADGq6vKQ3C/urJpglemTz+ctFcbqatwjKv6oyHBq+rO3qlscFJ7VVnuVexV"
    encoded .= "bT0fpr2y4fYqrDaSkl5Ve+X726v64eylI8QFe2Ule2Vle1XSZJUe8FbrFaTZq8pVOGuv7Ir26iIt1GmvvBzErdgrX7VDa8LKvXaDb7JXjcEr//bLX/DMF79m"
    encoded .= "5V25vbpy9Y5i9RV5/I9Heas7aXWfl7/1e97wZju3V03e6tG/v3JRM2hmL/7qCyrLqhirU2/VNgDeM1zV9l7LiDdcbci+6Ku41M1U0Sx5uCFn5+Zy+YbB3y3h"
    encoded .= "Qf/4FQs9sAAAHoa9Gh28csHZZFamJtsmCV65vmWblQ0ODl7ZjZUN2u5Nr7BXM9kr39JeWdFeleXLfvbKMvYqEAq1LEwUhPHSeVebAs9MaiJezhkl7dWKZSv1"
    encoded .= "qm/o2j67vfLVm9nqpAfdLdubywY9uq8F9ioMXn375S8ws8cOS6kZvKa6ippunfKF337u/qvOUleP+MRH7OVvOf/5s7/z5cpi7//oPHX11Re0GauUtPJZOx+N"
    encoded .= "016t/a8W1xdVOtRXOqjrBX/1Ifzd61zvbLU0jDIRWAAAh7sTZoJX42oGrT14FX/nN0nwSrNX1wtemdivPVJl/fbK1V5srn0O6VK+uIS1soLuqfcqrODW9qr6"
    encoded .= "WVzRXrm2ra7tK6198nh7VXtk9mvbq+oOCUTPHvbKy0V5gb3ytL1y1V4JEsBrMy3uZ68q4aNx9sqrgbhKkympZfveZYNrF9M4ePXIW9398Nsvf8Hznv26qadM"
    encoded .= "5YrXo65K927Pj0JOfnVmrz7xkdpd/GVveYky+PzER75w/59vePMrGkawVW9VHcns7i58kHES/tob32YlU+XZFb08LpeOHu21g9OfLHxRNukg7a8QWAAAA++w"
    encoded .= "qZpBS3bu3DJ41dR7S9NxMwSvkvZq4+BV8A67BK/saE2vivaqtqiMvaqKl1uyV7FJ9fBUHGSvfAZ7VfpnOYbh9Sd43XO5Z68AOXtljfbKFHu1+t+ZOJILwq7V"
    encoded .= "Xtmm9krb2FuyV67EJ4v1ps988Wv3Hda3Xva46fjznv3GqiRT1JVwudtUXa1cNX/4r551vPqyJ11VxVtl7VXZWLk8nhs+MN7oHZY27xS+cBGFVLJBuzb2W+ws"
    encoded .= "6dUhs06vvHWX5dnVRmABABxYXdkVgld96iphr7QZGL1jTfRxY7gawb7OGLQWexUpvGOWDdp1m14VBWTVLrl+JKfslSvPAdirPnsVnpgVVbRur8o7x4NtqU47"
    encoded .= "KDfSrpzrrgmFWkKl6hGy9soLu65SyLaFvbJ2e+UT2yv38GDrsFfNTa9qjee8HtssBK/uL+GZZ7/up/bKzL71su8ws+c/0lhXV1fqt2fnv1qtGfy9e/bKHlcL"
    encoded .= "Pv3By97y4pS6UrxVwVjlJjtslj9XrTGLhgNLo46pHw+LOttgm8+6/3E97dG+WGNnq7Xr8BJNOTh7LAuBBQAwVF3Zgwpe7VozaDcbvNrOXvWWDY6zV+4Nh1m+"
    encoded .= "6VWjvZInHMReaU+GPfbKq4v3yh51086QEfaqKxHTZa+8cLh5+Um+ZK8q53E52VTcaQPtlW9gr6zfXvm6wynZK3HCQXF7rdL0Kl2jakPKBsOpBk/W6nnPfv2+"
    encoded .= "wzKzb77sOx4/jj73zfKlybSawe3U1fp96Cx19Xu/+mXlwvPc73xldb2+8l1fu3zxi7/6wky3dal3Y4+JOl5nrMtTIOrIri21qKWWmsyyfMrp/il20qNdV2iV"
    encoded .= "LfDF1qddnP4zR2ABAPSbLWm+vJS6MoJXukQLxpvXDl7tWDZoEza9arRXV2h6hb2K7VVwiaqXHVmpaVTFXrlsr4RdFEQSmuxVzdqJ9Vw99kqYG7JgryovK0+5"
    encoded .= "WLNX3myv1v9ztL3q6dq+nb0SKyWttWX7bmWDYZmsm9nznv3Gt55IqxOT9dLnP/+5b2rBq3K7q1hdDagWfPT/fvivvqRsr+r9/mJv9YiXfPWF6iBUif5f31Xp"
    encoded .= "i9wy9XN5k1z6V8BrS/RSDiwbzrp/wC7lhvBnLw5LIJ/muw5UQ4jAAgAYoa5shuDVEHUlO6M+ezV78MqqJTm6QrpO8MrktsqiUgnf8fAt202ccDA+P49qr0yx"
    encoded .= "Vz7IXnm/vQpP/eZpB6tP5rW1qmsFs2A+w5yWMmnaQde6Frrgj6RpB4OO7IXjvtDzbIS9srntVdGTttmr5qZX9bJBqV979ah7+pbPf/Ybd+vyzZc+/77DevQf"
    encoded .= "3/Hct7ZWV+ENpTSOOEtdndorr948zn97qa5e/NUXqsOz1PeEmjnKGKutUznNy18GvNuyugJLzxJXcmB9ba1Oj9/lfjZrxZ8pi/Vz0za5zEJgAQC03e82UVe2"
    encoded .= "YfCq1aNp2meG4JXYyUJ0SzMEr0xpjl/f/9csGxzT9MoGt2zHXtWfAY9irzqmHQyclNW6ESlHw9ofxlphZcO8sL9Ve1U2ZIFSWfv8muxVHPbbwl4V73vNfa+u"
    encoded .= "Z6+8eq6K9mr97Evbq1Bdrdgrr1wOn//cN+87rEd846XPe2yyvvRtr13iXBtApdSVl+9zpdSVF+89mrd6RJS3ynw1N8BYbaWoNlZfntVbi+SzOpXWWqf3i4BU"
    encoded .= "wTppZYb3erRbLdkVLfbuPF+CjUdgAQAcTl2NslcePdFauv1W+YbU0jle1ggZe+WRmupXV+FqeLRbu4NXZgctGxQfz7cpG2ywVxU1q044iL0aaK9MslfhFTVb"
    encoded .= "45y0V7W5FbxynYunHSy30xZCMZV6rsrNomSv1g/3oBlT4WCo5aqkA06eK9D1EsiKvfKx9irTtX0Te6W2bE8XqFqi6ZUQvCpeBMvHyJO81VNv9dRkfc8zZvad"
    encoded .= "X1rWL0rKd3/KtAqBunr8/9bslZeHFyu/ylcL6sOaHmPVYSe8e1m7ZntKo4TaSixSNyt9Sy7+6u6gXFYXl4xlnZqs8iI0k7XM28odgQUAkLr7Pczg1Wh1ZQcI"
    encoded .= "XpkUrMjIEKmz6qB+7SbPgFgSDwe2V4kJBwfZK898jNUKqmCtZrdX2kXCqwdSrf5o7UKi2qu1l+u/7bJXwdWgepJ5af+sxbIK7kS0V+WO7OtnrWsXWi+cLvLP"
    encoded .= "K6qu1H6pyV5Zg70yZadV7FUl4tc24WBz06uxZYMeXQvP//0dz3370asfeas7vv49j1/4nV9aWmoGs+rqYsXP1JWZ/d6vfqV8++qMXLlshdqk1ZiKw06V1vLy"
    encoded .= "ZTuN4hW1VrwhLE2VerWb40kWa02PpXu0X+40Ly6z2sB9mS6DhcACAMirq8hjZLPZbtcKXinOLHwwVe5tieBVzhy5tNPivTEgeGWzlA3qRi3oRr5jy3YTsjmT"
    encoded .= "2SsPdv4G9sqH2itrsVfR3q4nOKw0q2D54ElNO1izV33TDor2ykbkYmqS1+OzydSeVsVjxOsqyoNjLjvtoJ9LmKqKql6makWXwX97uYWW5ydY3Ndebdz0qrNs"
    encoded .= "ULsiPVn0d37p218/dVj3TdYLvhzeqMaoq4K3Ki2lM3IlequstBogmtIN4jcchXvZbVmTP9LHxkvtJn0enuoLZ/lKVWExuJXp0V7ZwkU0WQgsAICj2qsoF5Uu"
    encoded .= "GxyrrozgVV4ebdyvXTeJo8sGXTwaM2WD1tSyvXIUzGavXNknVXvlru7tq9orb7FX1V3p0TNHMHNZr72q+JnQXlU1XC3SZdtMO7jyYLyeFfKEiLG6x1kpZ5OO"
    encoded .= "Hi2RFNs6D89xqcDQLT3BorsLF+WEp5vLXm3W9Coo17WoYnfVcflZ2eBdCMvMvnailZYXftmjG/KA1NW6urq46PUXCVprWZ7nB1AtI6WJx+jn/14k19X8HlYu"
    encoded .= "0rv8BJfcCpw2aLfaFIO1F12e00txHYpJsFlBYAEA9I4N2oNXcs2gJYJXrQWMaXt1zeBVNDyVJU6rurJhZYPp4JXF2Z/t7NXVywaxV5n16bRXNs5exU/C6w/S"
    encoded .= "sr2qHTdeP+3PqynrjduL76bPB1demcBeFT6GwF6tHQulxu1ef8rPNG7P2KvSMdcw7eAAe+W99spH2SsvurTEhIMb2qvOssFwqsFHv3zBlx7/19fOQ1H2Zy9Z"
    encoded .= "Tn3WM5UG79Vb/tP/iu3Vk/1WMVY7eCtv/9PVy+CUMipPteu6j7NahZiV1wWX3/ulLLPWOluVX2TZHu1pf4bAAgA4nMWSn8yr6soSwSvhkb7dXt128Ooo/drt"
    encoded .= "IZYNWnvTqz57FYqOA9srJeyg2yvfz15Zxl6VTnS5cXuzvarJBfHEqTZuL+2QtmkHSwemNu1gunG7Yq8qx1zPtIMd9qpyLI61V7aPvVInHKwZUlN8ca5s0MvR"
    encoded .= "RZePixd82c3say8pPlH/2Uu+ff+fL/rK83R1dVkzeGmv/uS7vy4OGNfUVeit9LBV699tZaw8/YtuQ9W7Kk8X48sAq9XQXep+DWJmtsFlGWK8lB7tvt0hg8AC"
    encoded .= "ALiGurIdg1ebqCsjeNW0DoPKBsPFNNurfPCqevjs1vSq1V5FxYkldXNFe2WT2isbY68sslfhyRJcWvXWV8K0g232yqwm2IrNm3qnHTSrt1EfOe2gF+yVpexV"
    encoded .= "5YMeNe2gMMVhxV65D7JXFtgrv469Kkw42NH0akjZYGA13ct3qXtlg34pre7zpy/+ljjKe8//9hX3//mb//oLj//ru9Vx4ou/+kLT5khWbgfxUvSEVq+B8AGv"
    encoded .= "2GVEntNPa2V4q7/Op5AS3aXWPtwlUnSuvvDeexfrBpdItk0JAgsAoOsOepDgVZe6ytir8GlVXpPaHf7qZYN7B69su7JBq6ZAgr3t5U3NNb1S7VVD8GpCe+Xi"
    encoded .= "AbOpvVJWt81eeWSvpEIkOQzipYvDqr2Sn4XqayVMO1j5lAPjVy688vLLPOl06mYqN4dgdN3yvL3yvL1yxV7ZZvbKsVdCD76W4FX9QvTCrzxjZn/24m9nh3Fn"
    encoded .= "0mrFXnWqK29qJdk+8MkMLg8gqraQXIsonaKRiT4nYrpd1X1BFay0u7wuJ8tcn5jwUCYLgQUAsIe6Mq2mrk1dddsrF2RSUl0J9mqj4FXwIh8RvKq9R2Lmx7Fl"
    encoded .= "g9W3dsVTYK8qB9HN2SsXT7J6e5rR9io8YVV7VfqnXDy4cmi4eHjXG7fX5VEtU1W++1TslSuPxg3TDmoizKpzBZb+20UHV7JXlRX22F7ZjdmrcRMO5soGpX7t"
    encoded .= "62d7cItamb7ytFrw6a//9MXfHGWvXvzVF1SdWnBFH5ph75dWt6SrOrd60WVW4VayCIbs7JCVTNa9/1d+Cz97yaKNkC9e7ff/7ZNrLAQWAMDm9mqb4NUQdWVC"
    encoded .= "8MrFPXOs4FWTvQr3R0/ZYL6Cb/qyQcVebdiyHXvVZa+8Zq/WDx6PdkJor4ZOOxhujlQ86NWLgZePJS8fobs1brei+vFQDxUPoHGN20vTDrpycpfOV2lWRM93"
    encoded .= "+CrObnAT9qq3ZXu2bLA3eFUVtE835ru+8vzLxVy2u7rrdfXd9p3V6XSr6qo3ciV6q0wTik5j5WOWnGZp/N0gq7VkZNbZubBoqyv1qlp7i6W4RnJnq9VX2/0M"
    encoded .= "1nkn/OlMFgILAGBDdWVXC14pQxGCV7o/sv2DV3aNskHpIGxuenVj9squY6/KO0986GmwV8rZlrTYob0yyV75tvaqsLvr0cXKRTGo+C431S4nkrSzWJt2sLjT"
    encoded .= "sq2vIoUU9PkqXrIKkzKUhNc4e1X5LKJyyyPYq54q3dBeNZQNqsEr7Sokqau1Y0wcBHZGrqRvI/PeSjZW3ruc8Rqp8p6LR3JrGbsuKzMMajJrdeLDpTbSzZms"
    encoded .= "9TU6N11Lw9Iu/nS6NB4CCwBgK3vllmuj6cpNoil4ZcmarR2DV0ofqTmCV+32KrRNG9mreqvzNnvVUTaYs1ceC6Uue+UVuaA+hPh17JUkH4qPwi6shlu1jtCl"
    encoded .= "50avf9CxvUrNYxo9ldW69lj07D2qcXtZhaweTQXnXYkbFcWKCw+tQeN2z9sr14+5jtZXUeP2dbW0+t9eO13rf6LtsduzV2rTq8rEEULZYDp4dbaYwFs1qytv"
    encoded .= "jTCbae1LU9JKGUCmv4Id6IE2XOiiDCoW6Ueiz5LCSTW/tPbXQdf1insqmrNcIOvUZLm2IggsAIADSCzRPmxWM2gErxQTo34M4ZzLHr7qWmWD+pGg/NGMTa+i"
    encoded .= "g2gXe1WcN+/W7FXFbIy2V+aesVfr+6992sHiB+CrPa9WSwLTjdurx+9lX+3exu3Vtlqe0jqmRjVW9UHCOm3VuN0LuyzRLCw9UWPluL+yvUpX6XacaEPLBpuC"
    encoded .= "V9dQV3t6K2n04dk/vLql6l+JRRweNxQrnl2EF02Grce3ij4r06C9tli/W0aLyTKhuACBBQBwLHvlgtIYEbxqbdZuWhAm59GkTdwpeGXblg1OFryyqza9Gmyv"
    encoded .= "PH+4p/pSxc8k4Z65gr0y2V7FJ4LHj2Ble1WddnCAvfKcvept3F7ehV7eY165GsQTFK7v4Xkbt3vlGKg0bnddeBUr/gJ7ZXl7ZYq9qvgSpXF7tUay0l9sE3tV"
    encoded .= "Nq2yveqecDBbNrhN8OrJ/7v0VivqyqQmhqaFnkeoK70JVfzjxKBrgKvaR3Is7eu6tLwu1/Ld7/1SlVlLYLlOWq63mKyTZeQ6W03dxx2BBQAw1F7lgleJmkEb"
    encoded .= "Erwaoa6Ch2JxTXZUV6nB3Ph+7crqhB9EZ/DKNiobtLigb3J75SlVtLG9ijdZbFbl4TmVtleFgruKdHNp7wWnZspe9bW+st7G7UH3ca88zIcnquJ0osuUC2LF"
    encoded .= "JBk3rPWV8N+etVfKBJnWN+1g1J9+Ynu1y4SDQ+2VFrz64Z/4ntI58Hu/+uW2+TcGqSuPRgyit8pKq4HGapIQTrgay2ifFTimixedyqwltUVL/UBcnsbFWk3W"
    encoded .= "PSW1qIpq0rkoEVgAAGNuoil1ZcOCV0prmCHBq1Bd2dGDV8GQW1+B2coG47HzDE2vVHslfMeMvdrAXrlwznvDtIO113smXSXZq7KJc/XsyDdur5655YbitTq4"
    encoded .= "2oSy6dZX1tL6qqJ+XLRXymGXvyUPbNyes1fFA7E6qWVkr+zo9iosYK1eNITglaCuXFNX5QFOUV0JkastvJXQ4K9paDupreg2XEtGHLW8dM17pRpaWRiMenoC"
    encoded .= "L2rV4rqienROLffWU10aAgsA4Kbujursx4lRwkMKXqUk2h7BK9uobFB+98KIWj8Srt/0KmevvPyQvemEg7PYKzukvfKcvTJh2kGP7JWXVFf9WuFluWBR66vK"
    encoded .= "02ipLO5sS7x8Su/TuL14SGilcGuvKdWRV5p1l46f7tZXFu202ma6tisKh0/BtcRZOblMcmd7FTW9Cu5yLl18+soG3/ITL60PFH73V7/85G2qXcimVle6t2q2"
    encoded .= "Tm52eGXVOnRfumWW6f3bzZ/4ohEm696khXdVi0t6gXdHz73GWYPmcERgAQBMb682CF41qis7cPAq33hrvL0aGrw6fNngcHvl6jG2n73yzG7xYKr0PnsVNfr2"
    encoded .= "6nb3aYRWexW4qUtJ5Al7VTojAgXoyjNiyl55aK+8vpplNV69QHnsfczKzZ4qa5TpV9X4AL5WYnnV1lfhHIJageT5DxR7tW6QaoeWaK/s2vaqUHjqG5YNiuqq"
    encoded .= "PG+Ib6yuPPjTBm+Vm/8kOZzbc6icXs54k7KESstT759XX0+OjGWQyXqinbpN1nJyaM1vshBYAACN92ObN3jlwiIOFrxKbU2qfekIexXamqOVDZqFvqZmPdrs"
    encoded .= "1SYTDt6qvfKavSqrlZLfrO5ecc6v6m7M2av8tIO165R+ram3vqoct15fSKmgMtylyiR6tUPAIj3kwdUk1/qqXDwYG67zwzBvr1zdY/GxED+Dqx7Q6ydIu70q"
    encoded .= "HlfXsFf9Ta9OFvbWn3iZODj73V/9snbx8fCqFGadvfGmmRmzDfZWmRFqvCRPXT27VZX3/HF+ib6cLTZXWpdUX08nGVR6ZVVXxe+v7+N/LNICTzXWsnKwLTRx"
    encoded .= "BwC4KaeVGxgIE9HuF7waoq7s1oJXps0qGSqk/uCVRaVMyv7vs1fiF8hDWrZn7JVQMBcO37FXur1aX/mwcXt+2sHgTb26kiNaX8WTJza1vvI5Wl95nKCz7Vpf"
    encoded .= "VZaTqQQMSm2lxu3r5+2Axu1BraWlaiStx175HvYq1fTq7X/9lVuMwdbUlXXXDHom+tmvrsTCwZQaapVWuQmIxo6newyVt/2ZOpC+X6iXllmSR/J73dmX5iWf"
    encoded .= "KKm7M7S+wNOlrffLook7AMCDtFeDglcD1JW2Mi6Mg/JfJ1aHw6pEi7bmysGrDezVocsGTU9FbTnhIPaqYK/ipyl3wV55ZK/M44uD0PqqcBxqqktqfVXYikLx"
    encoded .= "YBx+aWt9VS3lU3NV6+tU0zEmWicPnpATCqn63YGnLkKeFGddra+U97K8vaool3Z7pZ2nG9qrgQ/Av/srX6reMzqDV2PVVXj8KhdFfdflZz7IDWKvO+AeKLaW"
    encoded .= "1vc/nV5QbGalx7KedGf30xcLsyouZY11YrKEpckzEyKwAABuWF3tGLyKZ6HZrmYwb6/61dUO/dqT8z+6uhMOWDZoTU2vzLBXqr1KrFKTvVrdx9F37C32KlxM"
    encoded .= "EH9JNm5fmc5sv8btJpXKpltfVZIklVK47pI3SegH25dpfVV6a2sqHlw/wLw4u2Ku9ZU47aAlNrPSUq22x9L2yo9sr37nV55bO0y1aTd805rBZnWllApu4K3S"
    encoded .= "rVoPMRxvcFM+QmndP3sXuV+UEMt6Ko/ujvdF/5vqz1xY2pE0FgILACBrrwapq3oAo0EYzRy8Mr1s0Bu2Rl+NQwSv7Bplg1doenVL9ko96VZ3dTVN4P32qq1x"
    encoded .= "e4O9Chu31+yVBfYq/hhaH31qJY2Nra98cOsra2t95UJES2x9ZQWzY/VYUFAkqNorS7e+qvWtz9qrygWwsodr/ekr56P4/YRsr+wq9urpTvjwP/9CcJa5dply"
    encoded .= "08pGU/YqG7yqSONMtaC3DRqt6UvF7YzVzqZrSazL0rYJS3oPPO2kvmgLklqzl0yW1fpgWak7+8UJtUiLmlhjIbAAAFI6anzwyizxPZ5tGbyyag6h3V4lg1em"
    encoded .= "tc0PH+aa7FUyeJWZhnJs2WDGXjVP+L2bvZKiK9e2V15/jlXtlW1gr8Lx9dquSE47WO97pdgrD16vX+7Wnq4tEb+qnHC1PkSq52prfVX1Ph4fvd6nBLLFg4Lh"
    encoded .= "8mTrq0pzd8/ZK6+cdIl8WeXEjWowvX61V1Jm6xWpnrVXfk17FZ871UO1cg3PTDWYCl4lrXs8QBqirrJfJw6UVvtZKm/6/Xp7qgE+a0mu+l1f9kVbkGaylvN/"
    encoded .= "VJfsgsZ6+lO9OTwCCwDgoPZqRMfxy0Fp5j6dDF7lRkUPKHjVaK/CrL+rn3r5E7hC2eB89krocdtrr4IKx03tld6HWrNXlSO3xV6ZCS2J3OTUYe0JNvqkfa7W"
    encoded .= "V5VPUWt9VT/Uyw/ISvGgdunIahfhGbyhe3r5zNcuRcJio6lKt2l91TntoGivbIy9sn3sVdV0e/F0tm3LBj0pkrxXXSmZ1gZvNVhajXcVO9iP6iVwOfvlYhuH"
    encoded .= "s05M1opyKlunwCOtvrLaCuti85fiosXm8AgsAICDWazh6squHLxSuuJMErxyqXGEaK82CV7ZbZUNalIp37I9Y69cVUAPwF4FJ+9YexW3vvJgF1w+Vm/UuN3l"
    encoded .= "R3GrPopXypCEq26i9ZWXvVKm9VV0kCjFg3or7GphYK2OstSGfHDx4IpRcs1MrRz1GXvlQoFhwl5VllQuCfTqsVc53gp2eHd7FbX4V3uOWX12VBtfM9ilrnoj"
    encoded .= "V2O81Ui5NGvbrMvduJQiTO0zAFZevhZyKkeodI/kpWXWumHVNFbdZE338SKwAACuYK+y4wltVNQyNvLMkCgZvGpqG5+2V9693zctG3Rl069SNjiw6VX83XUu"
    encoded .= "7OeVkyxjr1Jlg/PaK8/bK8vbK5PslfXYq3jmvpUDxkNj4+pV2as7pGLUPFY593ZgqUYyvGV4feHllwmNmSof/x7Fg2sHmNbcPVk8WPtvT9ory0kUofWVa8eq"
    encoded .= "u2CvrJZDrMyNcGB7tW/w6irqalNvNUZD+Mg/2j/ac/ZhPi1AlKctzJQZPhVC62qosCx1kkHNjp2+rJipqma9EFgAADfmth5e8Cqu6BgTvIqHYGOCV3adssFk"
    encoded .= "xWI059217NXmLdut2qcr09/k4dgrz9sradrBIN8k2yuvPYSXPmwPrFD0oNrY+kr+IMu3A69dOGoN2oXiQXfh2uFC8aBWVRefTm3Fg5n7X/UnUau2hkfdRDSs"
    encoded .= "Yq+8ImrFLvteP9G0mT0rXybsZ6+GtWyP7FVTx6tcuytBXfVVC3Z5qwHSaiMR1rqosUbl7NNbwujR0iazhHK9snuSJhkMslVnL/PS+nrFiCGwAAAehr3qaNZu"
    encoded .= "xwxepdbkdoNXNm/Z4LFatsv2SppFb357JV9eVHtlQ+1V0HHJXbmUJZ4pvXqYNLW+EqRY2TVVs2NFc+ejigc9OJAjS1W68sQn8epH4Dkd01c8WDhb9ygeFLc9"
    encoded .= "TIgKra+8PBvAEHtV2nVT2Kt8y/aessEBwasR6moLb9XrHFxfjvhWI6WTb/k29w6VZVHePo5NFe1Q7fVroSkTJxmMTNZpd3ZNYyGwAAAehrraL3iV/nLv4MEr"
    encoded .= "F94gbp6a8kc2smww/e77lw1226tE06tD2SvP7AfXjpxisZoQKxDslTInquXsVckueXClGdS4vbP1lVtNH7vaJMsTxYPx5VosHqx+3OVZ6orn8fjiQYuKB+XO"
    encoded .= "XEHxoNUN19pR11c8qETVCh9oonG7xXuyErAMzmsv+1IpF9lkrzy+1p4fZ1pz//H2yhNjt/hylv+G7Kreyscnt5qWtox9m47FudT4fc1npaYXDGzRaSwrN8lg"
    encoded .= "1YsdW2MhsAAAWm6QysR7berKBgev4g4yaY+WswxJczRf8EpqX5a0VzOXDZo295jrn3Jsrzx/XN2CvfJme+WivYrP5aCBdPEccP1iI2179Z/RtIP137j+25q9"
    encoded .= "8rSWslosyDYpHgyKnrNGpmB2XDz+mvv0lO1VxYKVMlMuGK6zbfS6mQrO2nT7/JVDsaIjq22wXLFXa39TOUoLrxthry7/TO02Jly0Nw1exeqsQ13t460yM2zv"
    encoded .= "PcQepaFGKK21iQW197vXYUvVWIosu1hsUmOtLMoX2dEhsAAADmivdgleqd//EbwqDkynC15ZV9lgu72KJl8Sd/gN2itpZvSD26u2aQdrXqe19VX9YAxbX2mX"
    encoded .= "q/rnET5gJ1pfefmT9NgZBCeGlKsqH+bZ6QKTjy21p+9k8eDaliZvsOvnjCKe5A08Owo6W1+VTllJcvma9HTFXhXPAu2VU9urnYNXHp4Ou6irxqZufj0d4QP/"
    encoded .= "UtNQS7ysJb8arpisyw9rWf2TWh920WTd01hhMWLh18vj43qZuGoQgQUA0Hr/JHiVHw4pbxnKlWHBq1Z7NSZ4pR8VI4NXFbGj7PB80ytlXO7xp3Hb9sqG2itr"
    encoded .= "sFeFnebRo33ozrKN28PTbWDxYOUB28Ww5+qF3gUtZet1baaFiSrHV0PxYEkrbFA8WDFcpZTZrMWD2oyHlRNGbH1VuuhULliBKi1MOziwqdxge7VX06uO4FW/"
    encoded .= "uspUC7Z6K/U7xutbqp63WVpWZjl/yZJ79yX3t/ePn6VksoTW7KvLXIIZBk0NZB1EYyGwAACk+44SQ6reOJPqyjYNXs1UM2gzBq8yZYPu2rFznbLBtL2qHYSJ"
    encoded .= "lu3V7VZagR/bXsW2yofaKxfWxMW/qjZud/3TKnXb8eBNU8WDXl2PQa2vvFq0Vd7SsCv1ugfx8CF7vuLB/GXXXDBcpr2mWjzoXcWDlbBS6RwTNqGl9VW1cXv9"
    encoded .= "c69P39Jpr3x+e1W9RAldM02bsSGRrU5HrvLequnPZnRV2VVZmtff7/31ov690JG9fDgtK84qUwl4eXwufW2t7i6ZyzK1xEJgAQB03qeHBK82UVet9kp5k0HB"
    encoded .= "qz575eKXpll/tFPwajt7lSsbtOFNr5rtlUcPGwl75dEIbUt75Ve1V55P3kj2ygR75fUd6MHhUH4U96rqqje3iv5ZbdxefWUlU+rxZc2FGt6JigdrB3xP8aD2"
    encoded .= "7p4UZx0bmJgcoVo8mG59FYbpSvaqcskvXp795uzV6p/2lg1WBddk6mrjrlYzNkMaJLMq45Mgj3RurlIm66S91lJTTOpi79TY4mENYjXb5W42r8ZCYAEANN+z"
    encoded .= "pwpeDVFXypu0RsCGqqtU8Mp0q7hBv3ZrKxu05gLSaze92tVeefwxzmyvTLJX1QNyD3tVc0BK43a19ZWnTuDEromKB8WzvKd4MH7Q3qJ40PSDIBu/UorpxhUP"
    encoded .= "RjszUTxY2caS7PPc9kaXzHJEq3iBcOX4ci0eGOWOeuxVeKHZ0l51lQ2ODV51fTFm2Zq/1KJvz1htJrMuPgthPkJtbsHCGOBeb61gIsFFOiZ8MbOlU2MtNuFE"
    encoded .= "hAgsAIDWu2KHujKCV0fu135zZYPj7NXGLdtvzV65ZK8qU+4JaQPVXkX7JDykWhu3q5e1qxQPiuuTKR4sOB3tWpksHlQL4nz12qEmnqTjIPWc7L5+2srFg5Vt"
    encoded .= "dOsrHhTby+3V+sqq9sqLh254hQ9mOVi/2Ploe+XanH/j7VVr8MpbRgRt6mobb3V4aRVuWN+chn66iKjgLx3Ium+yrKiPVI1lZv6k1fvSprF8xoMCgQUAsLe9"
    encoded .= "koNXWuf4AerKrhu8skSD0m2CV1ft125jywY7m14NsFeunjbz2ytp4b32Kt5kddpBDzdE6i628iQdtr4K3zrU843Fg4G9WjkuhxUPunaQFHZs3Hbfg0MyygFp"
    encoded .= "H7Z6SXclaqR1rSr1/9I7YGvOtWHDNT8YbaM3pOTKra+KZ7AHJ1b9Cll3Wx48YQd/Uy7pHWivkk2vXFFT60uU7NVe6moDb3Wz0mpLk/VoEesZr2JH9pTJWu4f"
    encoded .= "QkufxjJffKm82jv3CAILAOBm1ZXtHbzKe7ScXMhro4fRr92uVTY4smW7e+rjvkl75eHe6LFXwmeg2yu1a7ZWwDiqcfsmra8yV0X3zG+LT8UjJt/cpnhQmMws"
    encoded .= "0bvdc8WDXpFohZ3gDb3bqz3aty0erPy3K68X75NeOjouLyxC66v6NJ3l61bTtIMle+Xj7VVPy3bXb/c+Kng15FuxppEK3mp/k3W5P5daN6ucxnp8OK0bKHEz"
    encoded .= "Hh0/jzVW4dWH0VgILAAA+UYVyKqR6sq2DF6Z2BxUenSMi5FuI3gV2auWFVAfkNubXnnwB332arcJB2/UXgmNXVR7FWyAJR72PBReHlyy5NZXlrxsrX8wyiUo"
    encoded .= "8UAuHHBe7m7v0YO02phZKh4MTu6skVEsmHboNDwhl0ODcYGh8N+14sGK4fJ88aCbFEOrmZqV4yzT+qqgjM5XZEDjdm2m0du2V9urK/fGc2pKb7XDuy9t67QM"
    encoded .= "2azl8ohZrL0p+8krH0epSn+pbIabP05zldfgABoLgQUAkH+UuGbwSik1HBK8GlczaFP2a0+MMscHr0wqA7Gdgldz2yulCVXdXnmkOI5vr8Y1bk9fP7JPaB5d"
    encoded .= "6eTiwfDJuTonlyuTJxY2qFY8WDFCHp4GyeJBz0suFyJa5+suSaKCkUnHr8L/Do719MxteVNbWf9K8aDkBz17Ae9ofdV0WoX2yqO89pb2Sp5wMFU22Ba86vtK"
    encoded .= "bAN1tae3mtmRLQkHNc5kPZFCHbbI72use/8/v0A/KUpsXw4CCwBgcn9V/gHBq+rYri94FW1co7oqByiy9qrVnU1qr+qfe4O9Cqbiykw4+MDslfpMvZW9qjVu"
    encoded .= "V1pfhSWlna2vLFseeO3iwdjXiBcajyRIf+92rfgu2tjE7ISlGkmPDZe6jVHv9sT6b1A8uP4ioXgwOqlLdzyXr8pevT+E9upMzYaKdQJ7tXnwald1Ncwl+dDl"
    encoded .= "X0+MeLg6Y9TN2lIel/Gt/aJBYy0FYaZrrHvZsLLGmtFhIbAAAMa5LOXRelCzdpsmeGVxg5v1h4DuEdzmwaton3rDsbF90yvPHQCSvfLsX+xjr6rvsou9soy9"
    encoded .= "soy9Eq1ktqTJqvZjVOP24jZ49eNOzRyvnvDp4sHaKnUUD7b3bndNVuSKBMfuZyUD5T7gzYObZc3SZosHk1ttTcWDxSW7cmcvqzpra31l8gnr+hU6VR5qo+yV"
    encoded .= "Fy9s29qrWdRVu7fyzZYsLuUawuRydZbNAlnlSsBkXeFpV/biO4UzDF5orMJaIbAAAA5vr/JzymwYvMqnwMqPQ4cLXunyaFzwyjYtGzTxq/zdm15dyV55+TOu"
    encoded .= "Tgu4pb2KrcT6GgenmNfevNjTKrZXwVNZl3/w5Fnp6im+UfGgB8WD+RNTLB6UezmZdoAUtIhHh8vl5iTjV5Ue7cXiwYrZKcev1sWT63Iq2rsu3jHd1w8tbRsl"
    encoded .= "u5wpHvRwS4PQn3xarX/O2vybwZnlobi7pr1yfeAnqithoHYldeUbLHOgTLpSAOjsCFiGB7JqEarc9IJR+CpKUfkjXbdBCm0znuGJFACgzv/79/+vfj54i4NX"
    encoded .= "gr1ywV55/1SDLqywuY+wVx7ZKxfNkQs7oPxhdNorF8oGt216JRXxyem+9T3fOeFgo73ycfbKr2uvfJi9ctFeefjAqIZ+ao/Igb0qHviF2q+ivaqu0abFg/Vz"
    encoded .= "U/XDQm/tyImUn49L8SuheLBidlxsMB86hqaH26z+bGiP5cniwfK+Ett+9e2FnYoHq1OC1udDyLW+So1TBHulHiYd9srr9srH2SsP09zuiSGmPl6svM6DPxBe"
    encoded .= "spdJmmBV/Mmw3sdszMoH5us/EJZZGA4W36l4/fDVhfzc/3265zISWAAA2dtPfDORnhRjdRWOUocErzoiYMrwcobgVaavqm1YNujqagr2quV96x7GtAM17G1U"
    encoded .= "s1f5CQeL9srmtFfWaq+s1V555mpUb30lPgCHfb8sXRnk1ZWMTUEiqKWlHKqr5OWj3ssHcEPxoHiVcvUSEl91tP9eP1ma4lel94qq0az/YdYr4iy4DiphOq/v"
    encoded .= "q+J7ef74rBQPSjI3sFcW26vktIOKvVIm8PT03LLxvXxs2WDniGLQqFR+3YzVYpVVXK7z7r70r8K9hNNaYsoqv65cEtZyYi4u6vEvDzAFIQILAGBLdTXUXrnw"
    encoded .= "fJhTV9L4S2nEE9orF3evy297e/3a9U/hkE2vHoy98lZ75eKDVvGYVtMz0bSD4Snf1/rKI3vl2Suby8+sfcWDlQkEXDhmIt8RffSuf2CZ+FU5muT5KSeDT0wu"
    encoded .= "HhQM1+Wx1xa/WjtE88WDguCXavNqk760FQ9WrkLS7ARrJ3Ry2kHrtVfeYK+83tkrO+GgUOKcHVHkrnzto9JBaguZVXNCratwuqCluH2LqLFO+7K3LOrxasyu"
    encoded .= "sRBYAABD7u+KVbjd4FVWa9Ufqm8leGWZskHpU/DmeqWr2iutbBB7FUxsVbuMqK2vpKfE2jkUh1G2bX3lqXbsmeJBE8+zoHhQ+CQaigerb1AwL8OfXINIUUkz"
    encoded .= "NNxuhfhV013cCxclF64wDfswmKgx2lduTXm8ypEmFw+mWl/VP6to/j/9uiRq20Z7NbbpVfSN1Nbq6ra9VX1jln3fcelfBQ/N0t3xvISLf9yXfel6s+X8v2aD"
    encoded .= "HlgAADH/w+//X+rD4hH2yos9jLzck2FlET7CXnmubLDYYPuq/dplexU0gmgtG/Sz/2/Fj1f5FNbaqrXZK69u8pHtlfoWE9or0+zV6u5JNG4v7Qy59VWwJ6NG"
    encoded .= "zuFhUA+JRP+sCWOXz2PPCYJK73bxUM9N/OX1I2TtUxwTv2r471qZZDl+Ff53W/xKeo4sZXwaerdXPiYPZ2So5JnnKh7U7VXxFPYWe+UHtVfea6+8/o2ZS1cT"
    encoded .= "n8Be+dD/XW3z3Cr9p7xhQR6+KNHWtvHN7p0Qf3O+BlhGAgsAoPPeNVPwakjNoKVqiDrKBjcMXtULe9SBpm0evLK5ygaPb6+k42kve2UpeyXO+jd62sGqvbLM"
    encoded .= "GRcflnHxYO3glHdloXhQfiavlliKgqBSlejxVbbSuz2aiSFjncIG6qYdQ4mLvnKzkeNXGcOlxa/y/52ow8sttvD5uPZ+VyoezDZuDyZpnNVeTRm8mjVy5Vd8"
    encoded .= "o3uBqGWHt1+CFVv07YiCVk/OiurUiB43tKq92dxFhAgsAIBB6ipSLkrgpU1dafZK6QW1T8crF/bO1csGw7GmR2OL+FUb2KsxZYOS2wmfpoQVWj+kbsNeeVxw"
    encoded .= "s5W9ypzbHh6favHg8NZXLcWDLp+vhbnKJI8gyCXlUpZoayUqD+UwjMWNtwid9diRB68J/7s8aWB00Ce/pal5kYbe7ZXXeOgHXbkqVkNm8VFn6eJBVy5w5Wud"
    encoded .= "R7cQqaLZpJLNG7RXPepqH4s0b0Hio31/4WKWLbZ/iffPIi7LQ/H26BwMywUljWWrom/WD5USQgAAidMqQl+fbLY8Dmy1V64Er1yJE8dFfUrwagN7tZ7/ruxa"
    encoded .= "j8oGw53mQcDaN7VXYQWfX2xRvO1jm17tZq98P3vlXfZKfy46XWrU20UsAjOhGKf2PtL0XtETdfFzkmaNywrlYDLB6s4ZWjzo2Q+jFr/SfJcrhkyJX3klmjQ6"
    encoded .= "ftXwsCeI2x7DVYtf6cuvFUh6rEMSLtLD3SXGr1yRKoKTqs606tH5Xm/eaFHcsjCFQMXH1uccvJ69Oh+jZevbPOpT0PK346TNJAWJiXVdW3kf+y65FamO7oWX"
    encoded .= "Ba+TOwheLudv/uNJI1gksAAAcnenVM2g3UjwaljNoM1eNtiprhR7NTh4ZVLTK/VQFGsNR9mr6GnPpaI1yV5Zl73ybeyVmh2Rnotzjdv3bH0VSkmPSpy083B8"
    encoded .= "8WDdcsWFk3FgKu6XlLMq6vWyuCghfqXGjgbEr8IrROMzZnhd9rZ9GW6Xh0tO9m4PBg3lM6u+Kz3Zfk64rFWvytJAqe3CWOgFsJu96jpgvfW83sgo3ULf90Ig"
    encoded .= "6WzTls63WBI7cwmfOZZwcY9fZ6U5CNW5BdX3uy4ILACAxE0p5VtS6sqiMqWMQVhZ37RHk4a88ppEY8acRNOFSX0d0mPNzuBV4lmzt2zQ+oqbmpterUyIHn7e"
    encoded .= "+9qrePk72it92kFlv8dXoIy9Up9drbf1VXjShsWD9dOvp3jQwz3g5YPZwx0i3lDcqv34inkVJX4VX2gGzQAYn5buNqzA0MfFr9ZPlqrFc+0MDP77bHdFpZSF"
    encoded .= "K6ucaqxIYSnSWP52orX1lXxdcj0rNthebVg2OJW6uqn5Cqsaa3WTlw2Wn3ute8lNXZqq9aWdzC2oaKypFRYlhAAAKv/D7//Dk5vB0I5Xp1MNhl5KCV6FVYiF"
    encoded .= "SQ9X/1WcaUXRRhd1fcJz2xb2qqNs0PvtlVo2aCPKBrvslU9sr0rb5qq9Cs6yze2VDbBX2pxmVvuruHF76JytVGPnuQujb1k8qD6FqTMPutKFPRUdzc8qOKC/"
    encoded .= "ePy8LcevXIpfhf/twt5siF+pBZINe85Tr/BA9VSvia4VnLqmVmIp7KniwdrVSGhQpslYdQHKyl7BXqWK1FwYnCX+sMPwHKY8sHMjt9sV3rLDWw63+pB7ZWPj"
    encoded .= "MfPP/uN5HRYJLACApnveIHVl44NXLgztbiJ4FQf7JWMxLHhlA8oG9a9sB5YN2pCmV2WpEz95JOxV/OBW2z+B19vDXpX3VLe9ytS2aZei7tZX8fm9cfFgcZ+0"
    encoded .= "hCZdPLUT8SutpMvLkqtoIrPxK6+Zgw3jV6XM2pj4leXjV5f6ZXT8qvYxibuzecaA/PhmfPFg9fqutL4Spx1czTHvYK9GB6/2TV3dsq6qb/OS3j/L6IUHfyFM"
    encoded .= "LHi2jJVX56JYk0ICCwAgwb/5/X+Yt1cuBK98XPAqetfu4JVlgldW+4K4L3i1h73KBK/K+1UPXsn2ygc2vbqGvfJbs1c23F5JT6GuVs4pxYPpSdiE1leuvD4+"
    encoded .= "v9b3kisaSjgF1PhVtdNdzXNpHsFduHCVDzDPXaGFO4M8oV5P/CrazN3jV4Oe8qX4Vfkwum8Z8/Gr8ioK8ava33uutWFj9bH+IikPGV+aD2yvBiak/GHaq47t"
    encoded .= "T8SyvHF1vDiozH2F7KmnFrOf/cffnvmzIoEFANBzuwtvTwSv1L2VGPW5aNDqC3L1mb9xd2eCV9UWN7GakQRNNKTf1V6V9rhW2TehvfL4+PGGp0JxsreBjdsT"
    encoded .= "1wn1HKyfb7XiwWp5YP2f1fiVsJla/Cr33FttT1Srbq5eonJNwTPxK3V+Dl1RnOuT9kkA0/Ere0jxKy0bvHbxqSeqEv/02glSOh1X4ldtra+8Ou3ghPbqisGr"
    encoded .= "By2tSrtjadyHS/1Fy6A1etqUfdH/+mQ5J396vCgWCSwAgBz/5vf+YfB9xtOfzRO8cpNaUWwWvPJgTVLBK98meCU2rPDYXvne9ur0cGopG2y2V95qr3wSe+Xb"
    encoded .= "2KvyikmJM+WJWJjQrP6UWH707Wl95ZXNqj0H5osHK0bQouLB6mca9G73+spX4i1qJyxNgpSK/lriVy7sfiV+ZdI+CXyAOLdc7rHcbzt+JWUbPTwx6x3lPFJd"
    encoded .= "4eecLx5ssFfWEZKNtmQWezUkLZVbiA/93yE0Vusu9Q0+Ni82z/PU9rgwh8jk8SsEFgBAm8P6b6P7URi8UtVVPIxxj0b5Ht0OXQleefyE7mUlEMke5fbu5dK5"
    encoded .= "kssRBJTlglcmlA3WPwsvf8a+T9mgyWWDVankZV0k2CtVk21tr7QXBn2UlSW3TPwl2atazqgQKOkWCPne+L56Mst7tN6OPVGZWF1foXd7/RDVehBd5GO8OX6l"
    encoded .= "bKcyQWFkXjIPfbUG3YPiV36D8StB1rm08LCvXHRa6U7I9PM9vbzG3vph66tYHPlV7ZXWrH0PdbWpcvInI4y7/81mw/oW7dr3xl0r5aklrn2TvHaqzG+vjBJC"
    encoded .= "AIDOG1xeXak3G2kM06Su6s9V+TUx4ZaarF5c39YdOl7Jg3JvWIHG4FVoT9Tv95P2ylo+j4Et2w9hr+QlF/aN1rh9gL2SHslcsFcetb5aObJdP0zU4kGvqi41"
    encoded .= "frX2r7B3X18XbW+9iLXFr5IBvNJPrhG/6njcS8zTOeKuX35FtB8a5nS1esP74pkfxa+ik06OXw0qHlTEW0/j9lnt1fbqats3aF5quju6tPylf9WXAdu+DF3s"
    encoded .= "SVlgriP7Remg27JsfwSMhgQWAEAL/+b3/lsleLL21DMqeGV7Ba/C2+EewatU/qv4go7glV42KJZw6mWD0WNMwl459io4QDeyV56wV9EqpacdrLkLy7W+kp6x"
    encoded .= "lPLqygaq/ZjTtUPnj9t64Y4mCFx8YLcwfhXnidJPhErMqqElk1UOQaVUtfbfnoxfNUS61j+9wjSR0msUp1KJXwU7WIxfiZ9Y/gxqcx3ZuRqsra2/if0Na/u3"
    encoded .= "yV417Rbf3V55fVA4Lss0ICE1bpWGrcyg1Rhoinx1opT8+Xh/eP2z//hbCCwAgFvmX98rJAyGaC6OUd1EYTSm41X95a4nnqy941U0NEh2vKp9Qdpur7y7bPBi"
    encoded .= "iZ1lg3ae6EvrpNknHPTCEG1Le+Vpe2WivRIPi5W3dP3TiWaa156sA50Vtb6Kn0U9rhetTS4gFA+6+Dy7djpp8Sv5OTz2HZpyquxWoa95ryqQ5E7w3y496nfl"
    encoded .= "pHzcYttDXy0xtMJFoOU4sR3jV6sHVjZ+pV205el5pRGPZZS4pb4XSH7M6gHSqVBqkyRvIK0GM3q5jT5r6I4auExf+c7I00eEmx/HXiGwAAD6HVbUsVEOXpny"
    encoded .= "DVwQvPIhwSvLBK+svWwwUle+VfBKN2hi8MoyZYPiHvCgj1Zr06tgwrOdJhwM+vmuPxKm7ZVvZK+EfsDV3sbeZq9qD6d5e1W5/JSLB6P9oP5F6eNW/ZTeJ0vv"
    encoded .= "3V570/AKlohfBWdBdH5l1l2xSw3xK2FGRm9YNSV+Zfn4lcf7QY1fRSXbufiVW0v8Kn9NdfkWv1H8qtYVLSlzmosH4w1KtwXYz15toq5mlla7mKz0Vmzg+4Z9"
    encoded .= "Fi1lrCev+Znj2CujBxYAwIZ3W3WKI01dmVDwF9ymlBvcPh2vFFPXlP+K5EYyeCWNOvUSzpmbXknVfK48uk5kr9THZU89o3l8ZNVWsGav5M9RFQVS43bFXllD"
    encoded .= "66vc06zldmvubDx9h0Lv9nqp1xbxKzdBuxwnfuWJn3v2UG59mve2QyW1+LHxKxscvwqlUByw0s5Zt2w3TuVTGVs86A0jsCPaq+Htw4cuY8QaLFst2OqL95Fv"
    encoded .= "/XhThizTzZf7a+7ZllgHggQWAEAX//r3/sGqCRhnr1woYhODV/HoZobglXnrjIflnba2DpnglddWQB2mymWDA5tenT5c1N80GtRdzV75VexVvV+vWpCSbFEz"
    encoded .= "ctpBE4p19N97QigXn3X7iwc995gtzuwWPfSuXqvF+FVOGcfxq65n1k7Dor62KX4lPaAVPg4vXKWk+NXlMVbtfpXYRg/O4kR8Vmgxph8byfhVpteeeso0xa9G"
    encoded .= "FA9q95HgQzqgvepO+uwatppghTaaRrA87B20IIt7Xly++c/8oyPFrwyBBQDQz5nDytQMuisDmAHBK6njld6Eody5vT5wkjpe6Y/WqeCVPqAVygbrH4dXd25T"
    encoded .= "8Moam165tGDh8X6MvfIme7W6i71sGI5lr7wiqKqfkYfnv9T6ym1E6yuheDD4xNXcR60eav3Q0Xq3h8361JVXU1reFr/yMH6V0SteX8lMa3O3vCwrbIKXagMH"
    encoded .= "PMkrzeary8p2/hLXsCF+JV3HM23XLJPbsih+lVHeXfGr2nVVulZ73l7lbcY+9sqDqVsGLXMqNl4/36YFezT07L3kuXwZ+pl/9M3DPXYhsAAAhjks90cPemoD"
    encoded .= "xTmCV2Ln+PqjpN9M8Eqs4nI9AOWJd6/snCh4tWXTq2H2yobYq3p12rT2yobYK9cezwa2vjKh9VXcYcqrWsbFa9UQqaE8rkfxq9rxol30pOdZb4lfbdLlqt0Z"
    encoded .= "eV9r9vrBm/ZFDZqho0w3u9sTGiVzdHl8vLr83t649tLjf0PFvwunZPLvEyfIFvbKO+zVQLPj86urcRvbsk+2eEcfsdSVIW9xkUe0V2bmy3LI0kcAeIB87tNf"
    encoded .= "MrOXvPRFM6/kf/bD/8eO8WhxRJkaQ46uGQwf7+bteGW54JU63mwtG5TfPVYM+ti4bq/ig6hRXZlUtLK+Y2/AXpki7/LTDoqN24sN+LzysRSfyJSZB4P4lVdO"
    encoded .= "sDXlV5h50Ku921viV146di67X2mTu/nqdqzFr7ywP7189notfrW+96o1cb727tVNvjiuPN5YL8S43NObuX781+oH3Qrb6Ml9tSJjvHh0F46rcvt2L5+5vrqy"
    encoded .= "K7m/ouf2oDK3PiuCl8/66Myy2syeXntt8Xqnxa984/jVxvaq21r0LehA0mqVZfe3WrbahGXcfrhc5EHV1SNIYAEAjOS//92/Xx0VjApeherrIMErywWvrJ4/"
    encoded .= "KpYN+sb2av1T0ssGt7FXjr06gL0yedpB+WUN9sra7ZUp9soy9qr6ITTuoJq9EvZC+eyM41d56VzQMelnzx3jV5kHch/x7t7zRkM3sHpF7PwEq+dD8VjR2655"
    encoded .= "/iRK7JZ4stz6JtVvMcUf6SveWzw43A+NKRvsyPD40e3VvtvgA9tXDd8Ur42SD22vDIEFADCcNYelTJjrWvDKE39vlY5Xpne8smLHq3D87oE18lzHq9o3oh48"
    encoded .= "Rqr+qNqvXS8b1HZCVd55/a09atleUwET2Cs/jL2KttB67FV1EjYvr0hv43atOmdE8aD+dF1etWLxoFefxLWkhFut9U+iX3PlSiJ3v6pfqlauivH6VX8Sdbbq"
    encoded .= "fI23dMVS4ldrx1b6vRLxq9JB1jC9Y02RVP4oqG8tXjNdfIe6d/bqtSSr9/JFpflCv4YuZ5K96o9fjbZXA5ZyG+rqetszpn1V4J76D47H32oe3V4ZJYQAcCAO"
    encoded .= "UUJ4nyflhMpXkF3N2k0on8uMm5XgVfeQ0VvzXwl5Epcldgev6gs9Vtmg7WuvBDMTPPPsZa98K3s1ovXVaqP4McWDF+eo14+0Ui/2zYsHbTXscbaa5fhVqc5r"
    encoded .= "fYd6acPOZUfxsPByF/1yNZwksHz1OdtrpWF71w+uVcMNqB/02k7es37QS1cmrX6wcoRXury7e/n8qlSkli9BviawvHDt10+u8ljHg/iVa1NbbF08aHFXfP0+"
    encoded .= "3a+ehtirm/JWlyxXeK9lszVf+hby0//oG7fxqZLAAgDYiv/+d//+TMEruYCx114NDl7ZNsErk4NXCXvl98fPhysbHGuvfEZ7ZXvaq+gHYxq3b2WvhLqIMEax"
    encoded .= "V/GgJ1fTXD3dtohfFVdOLK3LTD4YPECXJs7z4gla3f8DmrV7y3GW28aGaseGgJubPLFgTix4607rCAN5VeUkduhu8avoZS7dfU04xFsvPP0WaUjZ4I3bK9s3"
    encoded .= "iuVD33NIFeu9P7gZe2UksADgQBwugXXHf/7D/yfteSQ94c+44JULD4eKuoqt0UbBq8xqzNqvPV41j/d/T9OrekufxIGnzpwVyrraJnneXrm+W3R7VTr0vH70"
    encoded .= "qvbKKr1kBrS+Kj1Slo6Ecvyq8Na1qR+IX+0Qv7Ix7dvPN7kjfpVpu271+NX6mVrdxlL8qhIxK8WvVk6UqH37+duIEwJ4+Srv5Upjsbu/bRm/slr7diu2wL/8"
    encoded .= "YIKLZPFKkZ4oNpwJZnj8aoC9ujl1VVq9dm2xm/BYhr7tMmBrfvr/djvqCoEFAAisK2qsXnuVUlfd9io/6WFCNwywV0ODV9oKbGyvEm8dj6zrez4XvCo/hPTY"
    encoded .= "q4wmuwF7Vap0scrbKsWDWr5s1uLB0kNy7Rm7JKKUGeJsVaB6aK8Cm2PVyQfXejb5ikTywp6s7EPJ7Ah6RZI7kpFxZTa9tMAqiMJugTW4frAyqWW+frCo/Eyu"
    encoded .= "H3S9tZznzs3O+sFo8sH1q6k4+WD5Apv4nm/b4sEHa682Wofl6g5rGf3OS/sG3Z66QmABAALrWibrb/eoK5smeJUY0XluTfYIXo23V+lO0aVf5ssGbZ+mV9ir"
    encoded .= "4hq22Csb1ri9HL9qsVfl0jQvPod6tA892m+F+dEK3dm9tn/0+FW1F3UlfnX+2hHxK6tGWnxN61hT/GqAkRHiV5UuVGUblU6ZlSRdaXeZ3uGrob+YIOkqVrQY"
    encoded .= "v6rt5HKxsRBvrGcb6yfXVvGr1QX4uoSKxVQufhXcU2SBpZc8XqXv1VXs1RWV2TKHw2p/8yX9y1v1VggsAEBgTWCy3vK3w/FWj7qyYwSvlPHY1csGdwpe2TXK"
    encoded .= "Bge2bFfsldLQ6dD2ynaednBs66uHUzy4sooj4lfFWNC+8auKXtmlfbtL1XAD6gfHxK/mqx8sd8trqR9Mt283JdvY1759/crVGr+SJuTcI341s73a3yLNVqi4"
    encoded .= "XNthNb7/Iv3+5r0VAgsAEFhz8b97y98eZK9a1JWVvi5Nrckm9mqAurIgW7Vp8Opw9kp4x8KeG9Ky3YKuwNvbKxOLB4fbq41bX8VFf7K9Cg5BrXiw8qRbjV+t"
    encoded .= "PmDbBvGrciVna/zKLOzltF7wGOWJVj+gdPzKVrpW2ZiCuMb6wTCxZZvVD8aTBmrxK1lgiQdVXD+4dhVrrh9MnVyWqM+1IH5VEVgPNn51FHt1gMbwS6tIGmed"
    encoded .= "lkFL+6kHI60QWACAwAIAAAAAAIDD8Ay7AAAAAAAAAAAAZgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAA"
    encoded .= "AAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgA"
    encoded .= "AAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAA"
    encoded .= "YGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAA"
    encoded .= "AAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDU"
    encoded .= "ILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAA"
    encoded .= "AAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmJrnswsAAGbmhS/6DnYCAAAAAMDD5M/+9BvshEcgsAAA5gJjBQAAAAAAq08HD9lnIbAA"
    encoded .= "AKa7LQEAAAAAANQfHB6azEJgAQDMcgcCAAAAAABIPUo8HI2FwAIAuNrNBgAAAAAAYMiTxc2bLAQWAMB1bjAAAAAAAABjHzRuWGMhsAAAdr2jAAAAAAAAbPrQ"
    encoded .= "cZMa6xk+XQCA3W4kAAAAAAAAPH00QAILAICbBwAAAAAA3OBjyC1FsUhgAQBsftsAAAAAAADgeaQHBBYAAHcLAAAAAADgqWRqKCEEAOAmAQAAAAAAN/54cvRy"
    encoded .= "QhJYAACb3B4AAAAAAAB4ThkFAgsAgLsCAAAAAADwtDI1CCwAAO4HAAAAAADAM8vUILAAAB76nQAAAAAAAHhymRwEFgDAw70HAAAAAAAAzy+HAIEFAPAQr/4A"
    encoded .= "AAAAAMBTzIFAYAEAAAAAAAAAwNQgsAAAuiB+BQAAAAAAPMtsDQILAOChXPEBAAAAAAAO+kSDwAIAuP1rPQAAAAAAwKGfaxBYAAAAAAAAAAAwNQgsAIAWiF8B"
    encoded .= "AAAAAABPN7uBwAIAuM3rOwAAAAAAwM084yCwAAAAAAAAAABgahBYAAA5iF8BAAAAAABPOjuDwAIAAAAAAAAAgKlBYAEAJCB+BQAAAAAAPO/sDwILAAAAAAAA"
    encoded .= "AACmBoEFAAAAAAAAAABTg8ACAFChfhAAAAAAAHjquQoILAAAAAAAAAAAmBoEFgCABPErAAAAAADg2edaILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAA"
    encoded .= "AAAAAJgaBBYAQAwNsAAAAAAAgCegK4LAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAIAAOrgDAAAAAADPQdcFgQUA"
    encoded .= "AAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAA"
    encoded .= "pgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAA"
    encoded .= "AAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwN"
    encoded .= "AgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAA"
    encoded .= "AAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQW"
    encoded .= "AAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAA"
    encoded .= "AJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAA"
    encoded .= "AAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAw"
    encoded .= "NQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAA"
    encoded .= "AAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQ"
    encoded .= "WAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAA"
    encoded .= "AABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAA"
    encoded .= "AAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAA"
    encoded .= "wNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAA"
    encoded .= "AAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICp"
    encoded .= "QWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAA"
    encoded .= "AAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PA"
    encoded .= "AgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAA"
    encoded .= "AABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUA"
    encoded .= "AAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAA"
    encoded .= "pgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAA"
    encoded .= "AAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwN"
    encoded .= "AgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAA"
    encoded .= "AAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQW"
    encoded .= "AAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAA"
    encoded .= "AJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAA"
    encoded .= "AAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAw"
    encoded .= "NQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAA"
    encoded .= "AAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQ"
    encoded .= "WAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAA"
    encoded .= "AABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAA"
    encoded .= "AAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAA"
    encoded .= "wNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAA"
    encoded .= "AAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICp"
    encoded .= "QWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAA"
    encoded .= "AAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PA"
    encoded .= "AgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAA"
    encoded .= "AABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUA"
    encoded .= "AAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAA"
    encoded .= "pgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAA"
    encoded .= "AAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwN"
    encoded .= "AgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAA"
    encoded .= "AAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAwNQgsAAAAAAAAAACYGgQW"
    encoded .= "AAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAAAAAAADA1CCwAAAAAAAAA"
    encoded .= "AJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQWAAAAAAAAAAAMDUILAAA"
    encoded .= "AAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqUFgAQAAAAAAAADA1CCwAAAAAAAAAABgahBYAAAAAAAAAAAw"
    encoded .= "NQgsAAAAAAAAAACYGgQWAAAAAAAAAABMDQILAAAAAAAAAACmBoEFAAAAAAAAAABTg8ACAAAAAAAAAICpQWABAAAAAAAAAMDUILAAAAAAAAAAAGBqEFgAAAAA"
    encoded .= "AAAAADA1CCwAAAAAAAAAAJgaBBYAAAAAAAAAAEwNAgsAAAAAAAAAAKYGgQUAAAAAAAAAAFODwAIAAAAAAAAAgKlBYAEAAAAAAAAAwNQgsAAAAAAAAAAAYGoQ"
    encoded .= "WAAAAAAAAAAAMDUILAAAAAAAAAAAmBoEFgAAAAAAAAAATA0CCwAAAAAAAAAApgaBBQAAAAAAAAAAU4PAAgAAAAAAAACAqfn/t3cHK3FEQQBFZehAggv//zNd"
    encoded .= "SALZZBGQWamjTr9b3ed8gU4om7pUTwQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAA"
    encoded .= "ANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAA"
    encoded .= "AADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwA"
    encoded .= "AAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQs"
    encoded .= "AAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIE"
    encoded .= "LAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADS"
    encoded .= "BCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA"
    encoded .= "0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAA"
    encoded .= "ANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAA"
    encoded .= "AADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwA"
    encoded .= "AAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQs"
    encoded .= "AAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIE"
    encoded .= "LAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADS"
    encoded .= "BCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA"
    encoded .= "0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAA"
    encoded .= "ANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAA"
    encoded .= "AADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwA"
    encoded .= "AAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQs"
    encoded .= "AAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIE"
    encoded .= "LAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADS"
    encoded .= "BCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA"
    encoded .= "0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAA"
    encoded .= "ANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAA"
    encoded .= "AADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwA"
    encoded .= "AAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANIELAAAAADSBCwAAAAA0gQsAAAAANK2Y/96L8/+iTmdxyefAQAAAIdywIAlWnFy1yMgZgEAAHAAxwlY"
    encoded .= "uhW8MRdKFgAAAHOND1i6Fdw0KUoWAAAA4wwOWNIVfHpwZCwAAAAGGRmwpCv4liGSsQAAABjhMnTxBkwTAAAAJzHpAsuyDXcaK6dYAAAAlI25wFKvwHwBAABw"
    encoded .= "TjMClu0aTBkAAACnVX+F0FINO4+b1wkBAACoSV9gqVdg7gAAAKAbsGzRYPoAAADgIRuw7M9gBgEAAOC/i48AAAAAgLJiwHL6ASYRAAAAXuUClp0ZzCMAAABc"
    encoded .= "awUs2zLUmEoAAACW8x1YAAAAAKSFApZDD2gymwAAAKxVCVg2ZCgzoQAAACzkFUIAAAAA0hIBy3EH9JlTAAAAVnGBBQAAAEDa+oDlrAOmMK0AAAAs4QILAAAA"
    encoded .= "gDQBCwAAAIC0xQHLG0kwi5kFAABgfy6wAAAAAEgTsAAAAABIWxmwvIsEE5lcAAAAduYCCwAAAIA0AQsAAACANAELAAAAgLRlAcvX6MBc5hcAAIA9ucACAAAA"
    encoded .= "IE3AAgAAACBNwAIAAAAgTcACAAAAIE3AAgAAACBNwAIAAAAgTcACAAAAIE3AAgAAACBNwAIAAAAgTcACAAAAIE3AAgAAACBNwAIAAAAgTcACAAAAIE3AAgAA"
    encoded .= "ACBNwAJ4x5/ff30IAACAPWghAQsAAACANAELAAAAgDQBCwAAAIA0AQsAAACANAEL4H2+xx0AALABLSRgAQAAAJAmYAEAAACQJmABAAAAkCZgAXyIr8ECAADs"
    encoded .= "PqsIWAAAAACkCVgAH+UICwAAsPUsIWABAAAAkCZgAQAAAJAmYAHcwFuEAACAfWd/AhYAAAAAaQIWwG0cYQEAADadnQlYAAAAAKQJWAA3c4QFAADYcfYkYAEc"
    encoded .= "8+87AADAYbYbAQsAAACANAEL4JMcYQEAAPaafQhYAMf/Ww8AADB6oxGwAM7yFx8AAGDoLiNgAQAAAJAmYAF8lSMsAADAFnNXAhbAGf/6AwAA9pdBBCyA8z4D"
    encoded .= "AAAAm8sIAhbA2Z8EAACAnSVOwALwPAAAAGwraQIWgKcCAABgT0nb/BMC3OnZ8PPXDx8FAABQWE+mc4EF4DkBAADYStIELABPCwAAwD6S5hVCgD2eGV4nBAAA"
    encoded .= "dl5DjsQFFoDnBwAAYPtIc4EFsOtTxCkWAABw16XjkAQsgAVPFBkLAAD49kXjwAQsgJVPFyULAAD4+mZxeAIWwPrnjYwFAAB8YpU4DwELoPXsEbMAAIB3F4ez"
    encoded .= "EbAA0s8kPQsAAGwHCFgAnlgAAABpFx8BAAAAAGUCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAA"
    encoded .= "AGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAA"
    encoded .= "AABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYA"
    encoded .= "AAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIW"
    encoded .= "AAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkC"
    encoded .= "FgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABp"
    encoded .= "AhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAA"
    encoded .= "aQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAA"
    encoded .= "AGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAA"
    encoded .= "AABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYA"
    encoded .= "AAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIW"
    encoded .= "AAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkC"
    encoded .= "FgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABp"
    encoded .= "AhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGkCFgAAAABpAhYAAAAA"
    encoded .= "aQIWAAAAAGkCFgAAAABpAhYAAAAAaQIWAAAAAGnLAtbjkw8fpjK/AAAA7MkFFgAAAABpAhYAAAAAaQIWAAAAAGkrA5av0YGJTC4AAAA7c4EFAAAAQJqABQAA"
    encoded .= "AEDa4oDlXSSYxcwCAACwPxdYAAAAAKQJWAAAAACkrQ9Y3kiCKUwrAAAAS7jAAgAAACAtEbCcdUCfOQUAAGAVF1gAAAAApFUCluMOKDOhAAAALBS6wLIhQ5PZ"
    encoded .= "BAAAYC2vEAIAAACQ1gpYDj2gxlQCAACwXO4Cy7YM5hEAAACuFV8htDODSQQAAIBXvgMLAAAAgLRowHL6AWYQAAAA/uteYNmfwfQBAADAQ/wVQls0mDsAAADY"
    encoded .= "RuzSL8/+pWCncQMAAICaGV/ibq8GUwYAAMBpjflfCG3XYL4AAAA4p23Qz+p1QrjTWAEAAEDZZdxPbN8G0wQAAMCpbBN/aKdY8C1DBAAAACNsc390GQs+PTgA"
    encoded .= "AAAwyDb9F3jdxpUs+MikAAAAwDjbYX4TJQvemAsAAACYazver3S9sYtZnJBoBQAAwMFsx/71bPIAAAAA0118BAAAAACUCVgAAAAApAlYAAAAAKQJWAAAAACk"
    encoded .= "CVgAAAAApAlYAAAAAKQJWAAAAACkCVgAAAAApAlYAAAAAKQJWAAAAACkCVgAAAAApAlYAAAAAKQJWAAAAACkCVgAAAAApAlYAAAAAKQJWAAAAACkCVgAAAAA"
    encoded .= "pAlYAAAAAKQJWAAAAACkCVgAAAAApAlYAAAAAKQJWAAAAACk/QNO7GT2UYdJNgAAAABJRU5ErkJggg=="
    size := 0
    if !DllCall("Crypt32\CryptStringToBinaryW", "Str", encoded, "UInt", 0, "UInt", 1,
        "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        throw Error("Не удалось подготовить оформление.")
    bytes := Buffer(size)
    if !DllCall("Crypt32\CryptStringToBinaryW", "Str", encoded, "UInt", 0, "UInt", 1,
        "Ptr", bytes.Ptr, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        throw Error("Не удалось прочитать оформление.")
    file := FileOpen(target, "w")
    file.RawWrite(bytes, size)
    file.Close()
    return target
}

PauseCardFile()
{
    global ConfigDir
    target := ConfigDir "\pause-card-1.4.3.png"
    encoded := ""
    encoded .= "iVBORw0KGgoAAAANSUhEUgAAAUAAAAEyCAIAAAAEGJ43AAAExElEQVR4nO3ZQXKiABRFUXSabbj/DXWW0Rnbg5QpUwkJCAi3+pwFqJNb74On6/U6PMHb6zO+"
    encoded .= "BY7j5fKELzltGLBo4d1mMW8QsG5hzNolrxewbmG6lUpeI2DpwmMWZ7wsYOnCcgsyPj/+reqFVSxI6aEFli5sYf4Uz19g9cJG5sc1M2D1wqZmJjb5hJYuPNO0"
    encoded .= "c3raAqsXnmxadBMCVi/sYkJ6vwWsXtjRbwEu+B8Y2NuPAZtf2N2PGY4HrF44iPEYRwJWLxzKSJKegSHsu4DNLxzQd2F+CVi9cFhf8nRCQ9jngM0vHNznSC0w"
    encoded .= "hN0FbH4h4S5VCwxhAoawW8DuZwi5BWuBIUzAEHYeBvczBL29DhYY0gQMYQKGsNP175+9fwPwIAsMYQKGMAFDmIAhTMAQJmAIEzCECRjCBAxhAoYwAUOYgCFM"
    encoded .= "wBAmYAgTMIQJGMIEDGEChjABQ5iAIUzAECZgCBMwhAkYwgQMYQKGMAFDmIAhTMAQJmAIEzCECRjCBAxhAoYwAUOYgCFMwBAmYAgTMIQJGMIEDGEChjABQ5iA"
    encoded .= "IUzAECZgCBMwhAkYwgQMYQKGMAFDmIAhTMAQJmAIEzCECRjCBAxhAoYwAUOYgCFMwBAmYAgTMIQJGMIEDGEChjABQ5iAIUzAECZgCBMwhAkYwgQMYQKGMAFD"
    encoded .= "mIAhTMAQJmAIEzCECRjCBAxhAoYwAUOYgCFMwBAmYAgTMIQJGMIEDGEChjABQ5iAIUzAECZgCBMwhAkYwgQMYQKGMAFDmIAhTMAQJmAIEzCECRjCBAxhAoYw"
    encoded .= "AUOYgCFMwBAmYAgTMIQJGMIEDGEChjABQ5iAIUzAECZgCBMwhAkYwgQMYQKGMAFDmIAhTMAQJmAIEzCECRjCBAxhAoYwAUOYgCFMwBAmYAgTMIQJGMIEDGEC"
    encoded .= "hjABQ5iAIUzAECZgCBMwhAkYwgQMYQKGMAFDmIAhTMAQJmAIEzCECRjCBAxhAoYwAUOYgCFMwBAmYAgTMIQJGMIEDGEChjABQ5iAIUzAECZgCBMwhAkYwgQM"
    encoded .= "YQKGMAFDmIAhTMAQJmAIEzCECRjCBAxhAoYwAUOYgCFMwBAmYAgTMIQJGMIEDGEChjABQ5iAIUzAECZgCBMwhAkYwgQMYQKGMAFDmIAhTMAQJmAIEzCECRjC"
    encoded .= "BAxhAoYwAUOYgCFMwBAmYAgTMIQJGMIEDGEChjABQ5iAIUzAECZgCBMwhAkYwgQMYQKGMAFDmIAhTMAQJmAIEzCECRjCBAxhAoYwAUOYgCFMwBAmYAgTMIQJ"
    encoded .= "GMIEDGEChjABQ5iAIUzAEHYeXi57/wbgIS8XCwxhAoYwAUPYeRgGj8HQ83IZLDCkCRjCbgG7oiHkFqwFhjABQ9hdwK5oSLhL1QJD2OeAjTAc3OdILTCEfQnY"
    encoded .= "CMNhfcnzuwXWMBzQd2E6oSFsJGAjDIcykuT4AmsYDmI8xh9PaA3D7n7M0DMwhP0WsBGGHf0W4IQF1jDsYkJ6005oDcOTTYvudL1eZ3zo2+uDvwaYaM5eznyJ"
    encoded .= "ZYphUzMTm/8WWsOwkflxzTyh7zmnYS2P7uKC/4FNMaxiQUoLFviDKYbHLF7BNQJ+J2OYbqUDdr2APygZxqz94LlBwB+UDO82e2G0ZcD3xMz/5ilvef8BKCqM"
    encoded .= "VDy1qEIAAAAASUVORK5CYII="
    size := 0
    DllCall("Crypt32\CryptStringToBinaryW", "Str", encoded, "UInt", 0, "UInt", 1,
        "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0)
    bytes := Buffer(size)
    if !DllCall("Crypt32\CryptStringToBinaryW", "Str", encoded, "UInt", 0, "UInt", 1,
        "Ptr", bytes.Ptr, "UInt*", &size, "Ptr", 0, "Ptr", 0)
        throw Error("Не удалось подготовить карточку паузы.")
    file := FileOpen(target,"w")
    file.RawWrite(bytes,size)
    file.Close()
    return target
}

OverTestCanvas()
{
    global C
    if !C.Has("Canvas")
        return false
    point := Buffer(8,0), rect := Buffer(16,0)
    DllCall("GetCursorPos","Ptr",point)
    DllCall("GetWindowRect","Ptr",C["Canvas"].Hwnd,"Ptr",rect)
    x := NumGet(point,0,"Int"), y := NumGet(point,4,"Int")
    return x >= NumGet(rect,0,"Int") && x < NumGet(rect,8,"Int")
        && y >= NumGet(rect,4,"Int") && y < NumGet(rect,12,"Int")
}

UpdateTestHint(*)
{
    global C, Cfg, ModNames, Enabled, SettingsUI
    if !C.Has("TestHint") || !DllCall("IsWindowVisible", "Ptr", SettingsUI.Hwnd)
        return
    missing := ""
    for key in ["Mod1", "Mod2"] {
        index := Cfg[key]
        if index = 1
            continue
        name := ModNames[index]
        held := index = 5 ? (GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) : GetKeyState(name, "P")
        if !held
            missing .= (missing = "" ? "" : " + ") name
    }
    keyName := FriendlyTrigger(Cfg["Key"])
    tone := "82798E"
    if !Enabled {
        message := "Зум на паузе.`nНажми «Продолжить» слева."
        tone := "8B490E"
    } else if !WinActive("ahk_id " SettingsUI.Hwnd) || !OverTestCanvas() {
        message := "Наведи мышь на тестовый холст.`nЗажми настроенное сочетание."
    } else if missing != "" {
        message := "Зажми и удерживай " missing ".`nЗатем — " keyName "."
        tone := "8B490E"
    } else if !GetKeyState(Cfg["Key"], "P") {
        message := (Cfg["Mod1"] = 1 && Cfg["Mod2"] = 1 ? "" : "Модификаторы зажаты.`n") "Нажми и удерживай " keyName "."
        tone := "8B490E"
    } else if !GestureHeld() {
        message := "Отпусти лишние модификаторы.`nОставь только выбранное сочетание."
        tone := "8B490E"
    } else {
        message := "Сочетание зажато — всё готово.`nДвигай мышь " (C["Axis"].Value = 1 ? "вверх / вниз." : "влево / вправо.")
        tone := "4E2C9F"
    }
    if C["TestHint"].Text != message {
        C["TestHint"].Text := message
        C["TestHint"].SetFont("c" tone)
    }
}

FriendlyTrigger(key)
{
    names := Map("MButton", "колёсико мыши", "XButton1", "боковую кнопку X1",
        "XButton2", "боковую кнопку X2", "LButton", "левую кнопку мыши",
        "RButton", "правую кнопку мыши", "Space", "пробел")
    return names.Has(key) ? names[key] : key
}

ResetTest(*)
{
    global TestScale
    StopZoom()
    TestScale := 1.0
    RenderTest()
}

RenderTest()
{
    global C, TestScale, TestBitmap, TestPercentValue
    if !C.Has("Canvas")
        return
    bounds := Buffer(16,0)
    DllCall("GetClientRect","Ptr",C["Canvas"].Hwnd,"Ptr",bounds)
    w := NumGet(bounds,8,"Int"), h := NumGet(bounds,12,"Int")
    if w < 1 || h < 1
        return
    screen := DllCall("GetDC","Ptr",0,"Ptr")
    dc := DllCall("CreateCompatibleDC","Ptr",screen,"Ptr")
    bmp := DllCall("CreateCompatibleBitmap","Ptr",screen,"Int",w,"Int",h,"Ptr")
    DllCall("ReleaseDC","Ptr",0,"Ptr",screen)
    if !dc || !bmp {
        if dc
            DllCall("DeleteDC","Ptr",dc)
        if bmp
            DllCall("DeleteObject","Ptr",bmp)
        return
    }
    previous := DllCall("SelectObject","Ptr",dc,"Ptr",bmp,"Ptr")
    brush := DllCall("CreateSolidBrush","UInt",ColorRef("F6F3FC"),"Ptr")
    DllCall("FillRect","Ptr",dc,"Ptr",bounds,"Ptr",brush)
    DllCall("DeleteObject","Ptr",brush)
    spacing := Max(8,24*(w/248)*TestScale)
    pen := DllCall("CreatePen","Int",0,"Int",1,"UInt",ColorRef("E4DCF3"),"Ptr")
    oldPen := DllCall("SelectObject","Ptr",dc,"Ptr",pen,"Ptr")
    startX := Mod(w/2,spacing), startY := Mod(h/2,spacing)
    Loop Ceil(w/spacing)+1 {
        x := Round(startX+(A_Index-1)*spacing)
        DllCall("MoveToEx","Ptr",dc,"Int",x,"Int",0,"Ptr",0)
        DllCall("LineTo","Ptr",dc,"Int",x,"Int",h)
    }
    Loop Ceil(h/spacing)+1 {
        y := Round(startY+(A_Index-1)*spacing)
        DllCall("MoveToEx","Ptr",dc,"Int",0,"Int",y,"Ptr",0)
        DllCall("LineTo","Ptr",dc,"Int",w,"Int",y)
    }
    DllCall("SelectObject","Ptr",dc,"Ptr",oldPen)
    DllCall("DeleteObject","Ptr",pen)
    size := 80*(w/248)*TestScale
    SmoothRound(dc,w/2-size/2,h/2-size/2,size,size,18*(w/248)*TestScale,"805AFF")
    SmoothRound(dc,w/2-size*.2,h/2-size*.2,size*.4,size*.4,size*.2,"D8CBFF")
    MaskCanvasCorners(dc,w,h,18*A_ScreenDPI/96)
    DllCall("SelectObject","Ptr",dc,"Ptr",previous)
    DllCall("DeleteDC","Ptr",dc)
    ; Swap complete frames; owner drawing copies the frame without erasing.
    oldBitmap := TestBitmap
    TestBitmap := bmp
    DllCall("RedrawWindow", "Ptr", C["Canvas"].Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x101)
    if oldBitmap
        DllCall("DeleteObject", "Ptr", oldBitmap)
    percent := Round(TestScale*100) "%"
    if percent != TestPercentValue {
        TestPercentValue := percent
        DllCall("RedrawWindow", "Ptr", C["TestPercent"].Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x101)
    }
}

; Paint the outside of a rounded rectangle white into the completed frame.
; Alternate fill leaves the rounded interior intact, including its grid.
MaskCanvasCorners(dc,w,h,r)
{
    graphics := 0, path := 0, brush := 0
    DllCall("Gdiplus\GdipCreateFromHDC","Ptr",dc,"Ptr*",&graphics)
    DllCall("Gdiplus\GdipSetSmoothingMode","Ptr",graphics,"Int",4)
    DllCall("Gdiplus\GdipCreatePath","Int",0,"Ptr*",&path)
    DllCall("Gdiplus\GdipAddPathRectangle","Ptr",path,"Float",0,"Float",0,"Float",w,"Float",h)
    DllCall("Gdiplus\GdipStartPathFigure","Ptr",path)
    d := Min(r*2,w,h)
    for arc in [[0,0,180],[w-d,0,270],[w-d,h-d,0],[0,h-d,90]]
        DllCall("Gdiplus\GdipAddPathArc","Ptr",path,"Float",arc[1],"Float",arc[2],
            "Float",d,"Float",d,"Float",arc[3],"Float",90)
    DllCall("Gdiplus\GdipClosePathFigure","Ptr",path)
    DllCall("Gdiplus\GdipCreateSolidFill","UInt",0xFFFFFFFF,"Ptr*",&brush)
    DllCall("Gdiplus\GdipFillPath","Ptr",graphics,"Ptr",brush,"Ptr",path)
    DllCall("Gdiplus\GdipDeleteBrush","Ptr",brush)
    DllCall("Gdiplus\GdipDeletePath","Ptr",path)
    DllCall("Gdiplus\GdipDeleteGraphics","Ptr",graphics)
}

; Native DPI scaling handles coordinates. Measure text using the actual Windows
; font and physical client area to account for font substitution and rounding.
FitInterfaceText(*)
{
    global SettingsUI, TextLayouts
    if !DllCall("IsWindowVisible", "Ptr", SettingsUI.Hwnd)
        return
    for hwnd, item in TextLayouts
        FitLabel(item)
}

FitLabel(item)
{
    ctrl := item.Control
    text := ctrl.Text
    rect := Buffer(16,0)
    DllCall("GetClientRect","Ptr",ctrl.Hwnd,"Ptr",rect)
    width := NumGet(rect,8,"Int"), height := NumGet(rect,12,"Int")
    if width <= 0 || height <= 0
        return
    signature := text "|" width "|" height
    if item.Cache = signature
        return
    item.Cache := signature
    if item.CurrentSize != item.BaseSize {
        ctrl.SetFont("s" item.BaseSize)
        item.CurrentSize := item.BaseSize
    }
    if text = ""
        return
    dc := DllCall("GetDC","Ptr",ctrl.Hwnd,"Ptr")
    if !dc
        return
    try {
        Loop 12 {
            font := SendMessage(0x31,0,0,ctrl.Hwnd)
            previous := DllCall("SelectObject","Ptr",dc,"Ptr",font,"Ptr")
            bounds := Buffer(16,0)
            padding := Max(2,Round(A_ScreenDPI/96))
            NumPut("Int",Max(1,width-padding),"Int",height,bounds,8)
            DllCall("DrawTextW","Ptr",dc,"Str",text,"Int",-1,"Ptr",bounds,"UInt",0xC10)
            DllCall("SelectObject","Ptr",dc,"Ptr",previous)
            neededHeight := NumGet(bounds,12,"Int")
            neededWidth := NumGet(bounds,8,"Int")
            if neededHeight <= height-padding && neededWidth <= width-padding
                break
            nextSize := Max(7,item.CurrentSize-0.5)
            if nextSize = item.CurrentSize
                break
            ctrl.SetFont("s" nextSize)
            item.CurrentSize := nextSize
        }
    } finally {
        DllCall("ReleaseDC","Ptr",ctrl.Hwnd,"Ptr",dc)
    }
}
