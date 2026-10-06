#Requires AutoHotkey v2.0
#SingleInstance Force
; ZoomFlow 1.8.2 — Windows / AutoHotkey v2
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
BufferedText := Map()
ZoomSliders := Map()
DraggingSlider := 0
OnMessage 0x0201, SliderMouseDown
OnMessage 0x0202, SliderMouseUp
OnMessage 0x0100, SliderKeyDown
OnMessage 0x0087, SliderDialogCode
OnMessage 0x0007, SliderFocusChanged
OnMessage 0x0008, SliderFocusChanged
OnMessage 0x002B, DrawButton

SettingsUI := Gui("+DPIScale", "ZoomFlow — настройки")
BuildUI()
SetZoomWindowIcons()
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
    C["BrandIcon"] := SettingsUI.AddText("x16 y16 w44 h52 +0xD", "")
    TextAt("ZoomFlow", 64, 26, 126, 32, 16, "262234", true)
    TextAt("by Design Flow", 22, 75, 166, 22, 9, "82798E")
    names := ["Зум", "Управление", "Плавность", "Программа"]
    for i, name in names {
        C["Nav" i] := ButtonAt(name, 20, 130 + (i-1)*56, 160, 44, "nav" i)
        C["Nav" i].OnEvent("Click", SwitchPage.Bind(i))
    }
    C["PauseCard"] := SettingsUI.AddText("x20 y535 w160 h153 +0x400000D", "")
    C["State"] := SettingsUI.AddText("x36 y553 w132 h26 +0xD", "")
    C["State"].SetFont("s11 Bold", "Segoe UI")
    C["PauseDescription"] := BufferedLabel("x36 y592 w132 h38", "Управляй масштабом`nдвижением мыши.", "F4F0FF", "7B708E")
    C["PauseDescription"].SetFont("s9", "Segoe UI")
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
    C["AccelerationLabel"] := TextAt("",248,386,500,24,11,"262234",true)
    C["Acceleration"] := ControlAt("Slider","x248 y412 w500 h28 Range0-100 ToolTip NoTicks",Cfg["Acceleration"])
    C["GainLabel"] := TextAt("",248,444,280,24,10,"82798E")
    C["MaxGain"] := ControlAt("Slider","x548 y440 w200 h28 Range10-40 NoTicks",Cfg["MaxGain"])
    C["GainHint"] := TextAt("",248,473,500,32,9,"82798E")
    TextAt("Интервал обновления зума · мс",248,504,412,22,10,"82798E")
    C["Interval"] := ControlAt("DropDownList","x680 y506 w68",["10","15","20","30"])
    chosen := 1
    for i,n in [10,15,20,30] {
        if n = Cfg["Interval"]
            chosen := i
    }
    C["Interval"].Choose(chosen)
    TextAt("Как часто обновляется зум при движении мыши.`n10 мс — чаще; 30 мс — реже. Обычно выбирай 10 мс.",248,532,412,36,9,"82798E")

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
    ctrl := type = "Slider" ? ZoomSlider(options, value) : SettingsUI.Add(type, options, value)
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
    global TextLayouts, Pages, PageIndex
    options := "x" x " y" y " w" w " h" h
    if x >= 220 && y >= 172 {
        ctrl := BufferedLabel(options, text, y >= 600 ? "F7F6FA" : "FFFFFF", color)
        if PageIndex
            Pages[PageIndex].Push(ctrl)
    } else
        ctrl := ControlAt("Text", options " BackgroundTrans", text)
    ctrl.SetFont("s" size " c" color (bold ? " Bold" : " Norm"),"Segoe UI")
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
    EndSliderDrag()
    CurrentPage := index
    for number, controls in Pages {
        for ctrl in controls
            ctrl.Visible := number = index
    }
    Loop 4
        DllCall("InvalidateRect","Ptr",C["Nav" A_Index].Hwnd,"Ptr",0,"Int",true)
    titles := ["Зум", "Управление", "Плавность", "Программа"]
    SettingsUI.Title := "ZoomFlow 1.8.2 — " . titles[index]
    DllCall("RedrawWindow","Ptr",SettingsUI.Hwnd,"Ptr",0,"Ptr",0,"UInt",0x185)
}

DrawButton(wParam,lParam,*)
{
    global ButtonKinds, CurrentPage, Enabled, C, TestBitmap, TestPercentValue, PauseInk, ZoomSliders, BufferedText
    ; DRAWITEMSTRUCT layout differs between 32-bit and 64-bit Windows.
    hwndOffset := A_PtrSize = 8 ? 24 : 20
    hwnd := NumGet(lParam,hwndOffset,"Ptr")
    if C.Has("PauseCard") && hwnd = C["PauseCard"].Hwnd
        return DrawPausePanel(lParam, hwndOffset)
    if BufferedText.Has(hwnd)
        return DrawBufferedLabel(BufferedText[hwnd], lParam, hwndOffset)
    if ZoomSliders.Has(hwnd)
        return DrawZoomSlider(ZoomSliders[hwnd], lParam, hwndOffset)
    if C.Has("BrandIcon") && hwnd = C["BrandIcon"].Hwnd {
        DrawZoomBrand(NumGet(lParam,hwndOffset+A_PtrSize,"Ptr"), lParam+hwndOffset+2*A_PtrSize)
        return true
    }
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
        ? "выключено · передвинь ползунок" : Format("{:.2f}", C["Acceleration"].Value / 100))
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
    EndSliderDrag()
    SettingsUI.Hide()
    return true
}

ToggleEnabled(*)
{
    global Enabled, C, SettingsUI, PausePulseStart, PauseInk
    StopZoom()
    Enabled := !Enabled
    C["Pause"].Text := Enabled ? "Пауза" : "Продолжить"
    C["PauseDescription"].Background := Enabled ? "F4F0FF" : "FFF4DB"
    C["PauseDescription"].Redraw()
    SetTimer PulsePause, 0
    PauseInk := "7E420D"
    if !Enabled {
        PausePulseStart := A_TickCount
        SetTimer PulsePause, 33
    }
    for key in ["PauseCard", "State", "Pause"]
        DllCall("InvalidateRect", "Ptr", C[key].Hwnd, "Ptr", 0, "Int", false)
    UpdateTestHint()
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
    EndSliderDrag()
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


; These sliders use the same owner-draw button path as the visible action
; buttons, not the system trackbar's clipped custom-draw notification.
class ZoomSlider
{
    __New(options, initial)
    {
        global SettingsUI, ZoomSliders
        if !RegExMatch(options, "Range(-?\d+)-(-?\d+)", &range)
            throw Error("Slider range is missing")
        this.Min := Integer(range[1])
        this.Max := Integer(range[2])
        this.Current := Max(this.Min, Min(this.Max, initial))
        this.Handlers := []
        clean := RegExReplace(options, "\s*(Range-?\d+--?\d+|ToolTip|NoTicks)\b", "")
        this.Control := SettingsUI.AddButton(clean, "")
        ZoomSliders[this.Hwnd] := this
        DllCall("UxTheme\SetWindowTheme","Ptr",this.Hwnd,"Str","","Str","")
        DllCall("SendMessageW","Ptr",this.Hwnd,"UInt",0xF4,"UPtr",0xB,"Ptr",true)
        this.UpdateAccessibleName()
    }
    Hwnd {
        get => this.Control.Hwnd
    }
    Value {
        get => this.Current
        set {
            next := Round(Max(this.Min, Min(this.Max, value)))
            if next != this.Current {
                this.Current := next
                this.UpdateAccessibleName()
                this.Redraw()
            }
        }
    }
    Enabled {
        get => this.Control.Enabled
        set {
            if this.Control.Enabled != value {
                this.Control.Enabled := value
                this.Redraw()
            }
        }
    }
    Visible {
        get => this.Control.Visible
        set => this.Control.Visible := value
    }
    OnEvent(name, callback)
    {
        if name != "Change"
            throw Error("Unsupported slider event: " name)
        this.Handlers.Push(callback)
    }
    SetFromUser(value)
    {
        previous := this.Value
        this.Value := value
        if this.Value != previous {
            for handler in this.Handlers
                handler.Call(this, 0)
        }
    }
    UpdateAccessibleName()
    {
        this.Control.Text := this.Current " / " this.Max
    }
    Redraw()
    {
        DllCall("RedrawWindow","Ptr",this.Hwnd,"Ptr",0,"Ptr",0,"UInt",0x101)
    }
}

SliderMouseDown(wParam,lParam,msg,hwnd)
{
    global ZoomSliders, DraggingSlider
    if !ZoomSliders.Has(hwnd)
        return
    slider := ZoomSliders[hwnd]
    if !slider.Enabled
        return 0
    EndSliderDrag()
    DraggingSlider := hwnd
    DllCall("SetFocus","Ptr",hwnd)
    DllCall("SetCapture","Ptr",hwnd)
    SliderDragTick()
    SetTimer SliderDragTick, 16
    return 0
}

SliderMouseUp(wParam,lParam,msg,hwnd)
{
    global DraggingSlider
    if !DraggingSlider
        return
    UpdateSliderFromPointer()
    EndSliderDrag()
    return 0
}

SliderDragTick()
{
    global ZoomSliders, DraggingSlider
    if !DraggingSlider
        return
    slider := ZoomSliders[DraggingSlider]
    if !GetKeyState("LButton","P") || !slider.Enabled || !slider.Visible
        || DllCall("GetCapture","Ptr") != DraggingSlider {
        EndSliderDrag()
        return
    }
    UpdateSliderFromPointer()
}

UpdateSliderFromPointer()
{
    global ZoomSliders, DraggingSlider
    if !DraggingSlider
        return
    slider := ZoomSliders[DraggingSlider]
    if !slider.Enabled
        return
    point := Buffer(8,0), rect := Buffer(16,0)
    DllCall("GetCursorPos","Ptr",point)
    DllCall("ScreenToClient","Ptr",slider.Hwnd,"Ptr",point)
    DllCall("GetClientRect","Ptr",slider.Hwnd,"Ptr",rect)
    margin := 12*A_ScreenDPI/96
    length := Max(1,NumGet(rect,8,"Int")-2*margin)
    ratio := Max(0,Min(1,(NumGet(point,0,"Int")-margin)/length))
    slider.SetFromUser(slider.Min+ratio*(slider.Max-slider.Min))
}

EndSliderDrag()
{
    global DraggingSlider, ZoomSliders
    SetTimer SliderDragTick, 0
    previous := DraggingSlider
    DraggingSlider := 0
    if previous {
        if DllCall("GetCapture","Ptr") = previous
            DllCall("ReleaseCapture")
        if ZoomSliders.Has(previous)
            ZoomSliders[previous].Redraw()
    }
}

SliderKeyDown(key,lParam,msg,hwnd)
{
    global ZoomSliders
    if !ZoomSliders.Has(hwnd)
        return
    slider := ZoomSliders[hwnd]
    if !slider.Enabled
        return
    step := Max(1,Round((slider.Max-slider.Min)/10))
    switch key {
        case 0x25,0x28: next := slider.Value-1
        case 0x26,0x27: next := slider.Value+1
        case 0x21: next := slider.Value+step
        case 0x22: next := slider.Value-step
        case 0x24: next := slider.Min
        case 0x23: next := slider.Max
        default: return
    }
    slider.SetFromUser(next)
    return 0
}

SliderDialogCode(wParam,lParam,msg,hwnd)
{
    global ZoomSliders
    if ZoomSliders.Has(hwnd)
        return 0x0001 ; DLGC_WANTARROWS; Tab retains normal focus navigation.
}

SliderFocusChanged(wParam,lParam,msg,hwnd)
{
    global ZoomSliders
    if ZoomSliders.Has(hwnd)
        ZoomSliders[hwnd].Redraw()
}

DrawZoomSlider(slider, item, offset)
{
    target := NumGet(item,offset+A_PtrSize,"Ptr")
    rectOffset := offset+2*A_PtrSize
    width := NumGet(item,rectOffset+8,"Int")-NumGet(item,rectOffset,"Int")
    height := NumGet(item,rectOffset+12,"Int")-NumGet(item,rectOffset+4,"Int")
    if width < 1 || height < 1
        return true
    dc := DllCall("CreateCompatibleDC","Ptr",target,"Ptr")
    bmp := DllCall("CreateCompatibleBitmap","Ptr",target,"Int",width,"Int",height,"Ptr")
    if !dc || !bmp {
        if dc
            DllCall("DeleteDC","Ptr",dc)
        if bmp
            DllCall("DeleteObject","Ptr",bmp)
        return false
    }
    old := DllCall("SelectObject","Ptr",dc,"Ptr",bmp,"Ptr")
    try {
        bounds := Buffer(16,0)
        NumPut("Int",width,"Int",height,bounds,8)
        brush := DllCall("CreateSolidBrush","UInt",0xFFFFFF,"Ptr")
        DllCall("FillRect","Ptr",dc,"Ptr",bounds,"Ptr",brush)
        DllCall("DeleteObject","Ptr",brush)
        scale := A_ScreenDPI/96
        margin := 12*scale, cy := height/2, radius := 6*scale
        x := margin+(width-2*margin)*(slider.Value-slider.Min)/(slider.Max-slider.Min)
        available := slider.Enabled
        idle := available && slider.Min = 0 && slider.Value = 0
        track := available ? "EAE4F5" : "EFEDF3"
        ink := available ? "805AFF" : "CBC6D5"
        SmoothRound(dc,margin,cy-2*scale,width-2*margin,4*scale,2*scale,track)
        if available && !idle && x > margin
            SmoothRound(dc,margin,cy-2*scale,x-margin,4*scale,2*scale,ink)
        if available && DllCall("GetFocus","Ptr") = slider.Hwnd
            SmoothRound(dc,x-radius-3*scale,cy-radius-3*scale,
                2*radius+6*scale,2*radius+6*scale,radius+3*scale,"FFFFFF","C9B8EF")
        ; Off but available: white thumb with violet outline.
        SmoothRound(dc,x-radius,cy-radius,2*radius,2*radius,radius,
            idle ? "FFFFFF" : ink, idle ? "9D87CE" : "")
        DllCall("BitBlt","Ptr",target,"Int",0,"Int",0,"Int",width,"Int",height,
            "Ptr",dc,"Int",0,"Int",0,"UInt",0xCC0020)
    } finally {
        DllCall("SelectObject","Ptr",dc,"Ptr",old)
        DllCall("DeleteObject","Ptr",bmp)
        DllCall("DeleteDC","Ptr",dc)
    }
    return true
}

DrawZoomBrand(dc,rect)
{
    static icon := 0
    w := NumGet(rect,8,"Int")-NumGet(rect,0,"Int")
    h := NumGet(rect,12,"Int")-NumGet(rect,4,"Int")
    brush := DllCall("CreateSolidBrush","UInt",0xFFFFFF,"Ptr")
    DllCall("FillRect","Ptr",dc,"Ptr",rect,"Ptr",brush)
    DllCall("DeleteObject","Ptr",brush)
    unit := Min(w/44,h/52), size := Round(40*unit)
    if !icon
        icon := DllCall("LoadImageW","Ptr",0,"Str",ZoomIconFile(),"UInt",1,
            "Int",128,"Int",128,"UInt",0x10,"Ptr")
    if icon
        DllCall("DrawIconEx","Ptr",dc,"Int",Round(2*unit),"Int",Round(6*unit),
            "Ptr",icon,"Int",size,"Int",size,"UInt",0,"Ptr",0,"UInt",3)
}

SetZoomWindowIcons()
{
    global SettingsUI
    path := ZoomIconFile()
    TraySetIcon(path)
    for pair in [[0,16],[1,32]] {
        icon := DllCall("LoadImageW","Ptr",0,"Str",path,"UInt",1,
            "Int",Round(pair[2]*A_ScreenDPI/96),"Int",Round(pair[2]*A_ScreenDPI/96),
            "UInt",0x10,"Ptr")
        if icon
            SendMessage(0x80,pair[1],icon,SettingsUI.Hwnd)
    }
}

ZoomIconFile()
{
    global ConfigDir
    static target := ""
    if target != "" && FileExist(target)
        return target
    DirCreate(ConfigDir)
    target := ConfigDir "\zoomflow-loupe-1.8.ico"
    encoded := ""
    encoded .= "AAABAAcAEBAAAAAAIAAdAwAAdgAAABgYAAAAACAAWwUAAJMDAAAgIAAAAAAgAPIHAADuCAAAMDAAAAAAIACcDgAA4BAAAEBAAAAAACAAphcAAHwfAACAgAAA"
    encoded .= "AAAgABdHAAAiNwAAAAAAAAAAIAD84gAAOX4AAIlQTkcNChoKAAAADUlIRFIAAAAQAAAAEAgGAAAAH/P/YQAAAuRJREFUeJw1k01oXWUQhp8595x7b36amCoq"
    encoded .= "JSlSrVlUKIhYN66tKAguKlrcKEURwSxEBC1VXHQhLkRBdFEsCgoapIQGKxTRRhdS0YYgWlrRirYI+Wlyk3vPOd/M6+LExcxu3vl53jFJZmYC+OQV3b7SK9vu"
    encoded .= "HW31SwOoKqhgO0ErVL/+2dAlACEzgA9fKveRt94vB9rfH0SrqrE6QaqNOoE7SBACw1Jm2WLl6Zm3vugs2bvHNFr0qvOdoj29vFpGVWdZVUNyCIeUms7CGqFQ"
    encoded .= "DHeLbKusfxu0i3vyfGNwIHl3+vr1sq6TZWUl94CtDaMaQGcIqgGERHcE3GUbm1WdZe3pbj8dyPuljchRWZGVFZa8KZ7cAw8+aTZ+I1QlfD2Lfvwm6AyDhEWg"
    encoded .= "kI/mgwFCWFk14/Y3jck9xnPHsfNfoW9nxc1TxuMzWNHJdG7eGdkhCw9LTmSVQ1nC5rrR34TeOjz8FPb9HPr4TXHfQ2bn5sSJ19ADh7GiDXWN3AUOeUqQSnhs"
    encoded .= "JmPXbdifF0V3GH75Qcy8Y7bvXrhlt9mJY6i/ATftEv/8Ltpd4XLLvYII+G5eDI+i5Wtw+EVsdBzOfCRN7TWbP4nqBEUHeqsIE+7gkch8G9OlRfHTgvj1Z7Fw"
    encoded .= "Gj36vFlvDd57Wbq8KJ4+il37S1y5LFptSC7Cc+XJG4G8IzLBeBfOzjpFO9Ozx81W/21Q9jbF3fdnHHzC7MynobGJZvX8fyTujeNC0O6KuZOhhdOmnbdiK1fR"
    encoded .= "1b+DI0cjO/JqYe6ys59LYzuxPKI1UGARRAStkJBEd1S2viGWl6GVy4bG4IM3pKoPiJDTQtnAXnhk9Ya6P3yhRXv3Vtn3wEwSisZ9ChEBCiHB5ppiqLMjz9q9"
    encoded .= "K/1I+7O3T02sITuUPJawliJk7pi7zFMTkWThMnfZyFhG3q6Xas8OnbowsWbNS5oO3nGxMzm19666qotEDXVz3HqbEiSoc/KiqFfW/1j68tKdJcj+A6Nb2TjK"
    encoded .= "beL0AAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAFIklEQVR4nK2V24tfVxXHP2ufc36X+c0kjYPRGrVeGinpQ8WH1ruR"
    encoded .= "tClFMPSSmFK0YBuQQipWCCiWH+ODBaV9aApiW5BAH6aDYovRpqHUeGmkUYkXJhpjmtZaNZEmmZnM7Zy919eHfWYmf0A3bPY+h813fdda3/3d0I6pnSp4i8bO"
    encoded .= "y7BKgOFQYdeEpR9+Y+maQLW7Tn718pLKGJ2UAilBk0AOKULEUAJ3IcAFgSIWxunamsnvPm1/HQ4VJibMTUMFmzB/fN/inm7Z2R8I3bqBpoEY25nAPa8pgacM"
    encoded .= "ikCA2jUAjXsdm7T3e890Hh8OFQzgB/sWPt4r+y8tLNZarlUnJ8QaYjKlZERvgT2DSzl9aWXKAIS5GZ2qqKyOzSceebZztARQLB5IwNISdUpUmbkRE8Qk4iqo"
    encoded .= "rYGTg+ZA+b8ZhYxagY4nvg4cLaemVJz9TbOlqUWMFDHm8tRpjTXA8oJRL0MIOVhK0OlC1YWUtJoRWFG7zJ0tUztVlExTNFElbjQRYmPUK3VPmfXCHFz1Ibj+"
    encoded .= "Juw9mw13ePUEeunn4r+vQ2+Qm4+BEGaGS+Wv5yjLaWDQ5JybBuq2uZm5sTQPN+4ydtyLeYI3ToMF2LYL23qbceAhdOxF0R+9rGQOcjS+DpWQAeXQxHxIDiEY"
    encoded .= "l2bgo9uNHfea/f4F8fwB6cKbOfj4O+CO+82+/KDZuTdMZ0463X5LzITa2gZOZLXECMvLsDgPiwvG/Bx0R2DHHuwffxSTD0v/Owt3f8vsxt3Gmb/Bk0N04Zz4"
    encoded .= "/D1mTZ174C7kwtu+lNAyb2B0nTHYlEswdxHG32mMXQGTP0KdPrxrk7H5w9DtG1ddI87+Uxw9aLr5S9i6t8HivBMKIwlafEq2gP4O9RLcMzT7wLUY5KYdedaU"
    encoded .= "ovjXK2Lr7cb2u8yWl8TV18kePBB4+D7p9ZNQltAfwNxFUQWQtCrnkhOQyKyfeQJt2IgkmD0P3Z7YdrsxvlEcOyzePItuuw977SQ8/5R05qTY/gXDgYVZhGHu"
    encoded .= "GdmTYLotUXIIBbxywqmPg1lu1shYlui2O80efcD12im47lPG6b+gF6bEez8In74V+8Mv0Mx50RnJIjETSfByfcrCyrV0z5dmZCzrerAeLs2Kpx9D195g3P3N"
    encoded .= "wPiV8Ng+6dAB9JFPGvc/YnbF243pY2JhXphpRaLIxVhnc5ZpSjKUM3Fv/SVCbyB+dTDR6RW662tmN9wM/z4D3T628d3G7IXseLv3ml26GDhy0Fm/ofUsv8yu"
    encoded .= "3Vtn9FZm7V6C/gg6PJmY/p3xse2BK98nW140/eQJ8fKLrju/SrjpjoKvfLswIf3yp5F1G0BuawG0Yr2rQbKZIYhR1hs1/vOqNPloAkySE4Ioem5PfgeFAtt2"
    encoded .= "a8HehyqbveD8+be5H3P1KSs5h/vAfCWT1RJJa14fRejI+r0VMsJdJDc6XfH9YSOQXf/ZghQNjwLHFzdtTgaw95b6Z4VVtywuLzcuSrnw9hHJ3qJVbav1GpTP"
    encoded .= "mEFqREowth5mzhMHvdGqjgvPTR4ffC6rKNl+A0NmnhSd9jKK5K4kkZKTXCRPSu7K30kpRiVBCqY0c95jWWByDLQfIAyHCvsPV4cWlpphVXSqbtnrlKFXlaFX"
    encoded .= "FdarCutXwfpVaSNVwUhV2KAqGKzuS0aqgkEVbFD1q3WdwkarpWZmOHl89NCQ9slceaD3bK0/gxVfTJ7enzwVSuDyXJaUu54fFwOtqQ0co0yB4kxD89SP/zR2"
    encoded .= "ZIjCBNaKtQ3CWzSGrGH9H/ubQxm6uoZBAAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAHuUlEQVR4nK2XXYxdVRXHf2uf"
    encoded .= "c+7MnY+WTqmFFFJpECoEq1QeKCgfaqrggwYHlFRjgkGjiGCMikYKCdGICIFIeCDG+gDBGSUqCWCbBh00UsVWFCoUkY8p2kqZfswwc+89e++/D/uce+8MPnJy"
    encoded .= "T+4+59y711r/9f+vtQ4sObZufSxfeu+tOrZeoDftbf0XQmaYtm6VWxc43ZesXPClw0MMKERv3ud4D77+kwfve3v4pQsV0RyvZ+t57uabLYIMTEsckAkwTNtu"
    encoded .= "6HxeuC97H99pVjifjBPqM6bvGCEqPZN616q2lnpniD5mzp6N4kffm8zvSU4AmAxkE+O48TPQjxfKn440iy1zC9But2OIFr0XIRgxgK8M1wZ96HMixYEkMJAs"
    encoded .= "OWOgKFdkDTdQwHy7vP+lvPgMwOQk0U1M4C6ftHDvfOemkWaxZeZYp9Vqtb334Eu54M15j/NeLgRcCLiOx5XVOgZcFE4RJ8kJc4qWrqOq+9DxpZ9tla1mo7jy"
    encoded .= "5I6/aXLSwsQ4zgC2Xa81Ze7/GQJ5pwwWPVZDHYJ1ofexgrpGIoWKKkRFut/llAQyzCqEkMycEAEr33H7r4amHcACrQ/nLh9st0MM3swHoyzBl1CW0PbQ8RAq"
    encoded .= "wnmf0pA2tsQkqz0QqtKkmM4YQVEomgUfY5HlAzFkmwFygBjdqd4j7yFG4UMyFgKUfVHXpHLOaLeg00pOUEXuHDSahnMQvOqo60+6SvspilO7DvhIloU+2H2C"
    encoded .= "vqygryE3S2RszcNJ62D9RuOEtbKiAUdfhxf3mp7+k1iYg8ERw5ddtVUkVRI7GNFlPQeCU0aVb5/Y7UOCOlYwYoYvU5Sf+KJx3qVYXiwuJRddhk0/bzx4D3p2"
    encoded .= "j2iOGsGrlx6rfIgQq0KRA4QyWiBF7z0p8lrrMRlRSNBfdSO2/mxot+DJHfDKPtRpwXGr4KzzsLXr4Uvfx+690fTXJyLN4Vq6qgBQ3741Ah5yg06l+RB6sINh"
    encoded .= "DhbegE9el4z/+1/w8zvQ/he0qDb87kH0wU9hm7cYW76OvXy16eiRSF5U/EEQeygAOICgJLEQrEsWDMwZLk/Rrj3NOPcjMHsEHrhVOjAtiiH46OfMrrnNbOVq"
    encoded .= "KAbh1/eiPz4MoyuMCz+Gtd5IGYhSRWR1C1nXgeh7+Z6fhdnDMHfEmD2S1rOH4V3vgywzdj2CXn0ZosHRGTh9I5y6wXCF8frB5MRjP0O+FBvON5pDJDIqGe/W"
    encoded .= "EcU+Dsgpi9BegNM2GKefbV2duwx2/UasPhkDsW83ZDmc8wFjdEw2OJwkd/HlxswB+MtOcXC/OPCSceI6GB2DmYNS0cBQQqIfgbzWsByUHdi8xWzdGTWzE3Wb"
    encoded .= "IyaXpeQcmxGjY3DZNXUFSuhtukQGxtxRtON+MT8LWQZFASFgWayMV02LpQ6EmCL7xd3SKWf2t1ixe0pccU0qd8tXin1/h/tuRaMrYdMl2HGrYPv9poP7xd5d"
    encoded .= "aHg5tmI1dNqwMIfMybrdkaprssiBSAzJgekXxPNPq9tWXZaq3svPoo0XYu+5yHjmz5E9U2LuiNPZF2J5bvz2l+LgtHCGvftcY9UaY9/fxOHXRGPQFKIsUvFg"
    encoded .= "aQoAq/OSN2Ck0dfXEXkBu3bC5ivhvR/CnnnCtHsKhpbLdk6YVp0kFuZEUcDYSuOyazHv4dH7pNS01I267hGx8sABEF1duFOfr/qArxpSlsNrB8TE3SjPjU/f"
    encoded .= "YHbBx1OOH39ITNwpYtt05kbj2juwE9ZCKGHhDdHuRDOrmlFFQL2pEMVomdHrYn35QqksD42IqYcCxYBjy1cdl19r9sErxKsvpM3etgY78ZS65kLeEF+5NbO7"
    encoded .= "viE9OeVt2VjqDVKScB2w6ydhnRupLhgiRhGC8CUMjaAdE4rf/ULU7ikxtAzO2gQbzocVJ8Ke36NbrpZ2PiiyDPJCXHdbbudc4Dj8WqymowqBfhJSybC/Znfn"
    encoded .= "u5i8jaThYnhUPP+UtO8p09hqs+VjSV7HDjnN/DcSQuSZPZFiILf3X+ooS3H9Dxt2x9c62vVYYGikqraLKiHdTgnY4mFCvREyRFnHY40mDDTF0UNRL+6Neukf"
    encoded .= "0rGZQGMwMDAabGBQ3P2dUn94NFAUhhDX/aCwNW83OgvCtAQBCdX5j1W57OcCNXkqVcSYXLIcsqIeUqvGVIJzomjAnd8sZYZt2pyxMC+CBwWkKCymcCsHbLre"
    encoded .= "vCe/WjbqGgZLIxf1HKiutFAvfcGnMp7lcNe3Su2eiux/MfKfV8TgIMRgRNx014E8Ftvb0UfJORQVY3pz6Bmv60I1ZEVTpDeJqtI6fepRVHdc2z5ZkhfQbJpC"
    encoded .= "tIzYilnmtwO48XFltz9i+6IP25qNIo+iI0lJt30o9KUkIkta1pvPIGKI1ctMuje8DAYGkPfqDLjh3ON/ct+Ty58bH1dmQnbTVmx6x6HhxtCyhwfyxvnzrQ5B"
    encoded .= "saxsV4roGy77nasKTPdZzZl+YqezGMhHrYzzj4fO0CVn7GX+5h6/0/va1RtfHXLLj78lyn3WLF9hxmJCxtpoLc1qvYgHve/aoVRP2ocxbYuDzW9PPmELtc2+"
    encoded .= "l9PeS+NVF8+uRoMbY4jHS8FCZSTWi+AIlZBCDNX/MyBAqH9b6dyK6Jw7ZL7c/cDToweX2lpyyMbHlf2fB2/JkfbuDxr+B0L3qNlUmnyDAAAAAElFTkSuQmCC"
    encoded .= "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAOY0lEQVR4nL2Ze6xlVX3HP7+1z7nvxwwdBkIZfKCAIKIWHw1UtKhN25T6yJ1C06YPErG1IC1t"
    encoded .= "g9RkoKQRX1QCmlBsTFNJdG6lFWgtNdFR1PpAHXwMbwoOCiMzHWS4j7P3Xr9v/1hrP84d0IY03cnJvWfvtdb+Pb6/7+9xjJ95ybQDuxzCz177NNeuZ7WLPVvR"
    encoded .= "8jIOpmd1gCTbuVPFs3v9/921c0mFkD3T88EzbTKzCMTrr9dwei8nl6P6eVX0WYDoEGMBMRIBKPAIXkeToeggYQCVF8qL2ntylLcRS/AQrVkDhWNatcHgoWHF"
    encoded .= "nu3LVgIsLalYXrZ2VXMdptnOJRXbly3e8KdPHDGcnrlQCufF6CcMBkPDk/DuJIEdXCCl+3KIMX0X3Topvck9P8sfy/ewtFcA+VntkWDcK+wT66sr115968L+"
    encoded .= "p1NiTIGdO1Vs327xo5euvXGiGF4/LIrnro6gLEfuWESmulYSPr/II0Q35EIY7kl6l1F7knyj4MrKmnUSNEobmJImxaCYCBMDKOu4t4p62wf+efjvjYEPU6B5"
    encoded .= "8NG/WH/TcDD4lBNCWVYjdxUeCS5wN2JUK5C7tZZ3jQsZm3vt2v4rlbySL2Hj39XcNTcjhjCcNFx1XS194NNTn+p7IgDs2KGwfRm/4S/XX1QUxY11LdZHZeXO"
    encoded .= "MEZCdKhjhomM6Ja+x8YDSdA6QhWh7kFNOly5FAqGy5CshU3jhaSE4a7gYljXVVW7qwiDf7zkHJ28vIzv2KHQKpAtI7ldMygGM2WMtdyKulISsofv5nuyfvJG"
    encoded .= "HaFqhI4Qa4jRcLd2b58LNyqV/lf6NPDK3spKFTF6baGYdi+v7VOrNdC5/pLyFcNB8fWyinVde5ASXBQhqoNBglESKPZjoQcZFy2gk3VtTHjo1lro3d/I+E18"
    encoded .= "kLQwMy9sMKhUv/qamye+trSkIhx5cl7mekthgbp2j9mK7hBlyaoxWzX/X0VaGMXGO3VmoYx3eYKbx86ynr0mT1LL1WrQBniGUquUp7/u8iIYFvVWgJN/jA0+"
    encoded .= "sifpHeHlZQ11xBR7QSp1OJcS/puX9IKXMfx25gsBCJa+GVBbG6SyHNCeFMTUUqmRmS1YR7tgdQ2Cl0LK1oOUrsGjtlSJFi0JphYi7SdC5UKyjlnUEzhDIhRQ"
    encoded .= "lVCtd3mgQVQxhOEkWJHWyxt4qc0XNDGRlWksI2TJYbYFYHnZYpuJ3THUY46Md/cO37E5qMcwyeLZ2gWUIyjXYfEIeOEpxlHHwdymtOeJA/Dog2Lvg7DyE5ia"
    encoded .= "hSKMJ7Nk/S75KUPL6AoKubfk0ypQCwaHCS48QybGTrGWObwLzhBg5Uk48mg4683GS87ANm/lsMs98NjD4qu3odtvcdbXjckZULQseBbUuswcLFNvEye981oF"
    encoded .= "5IFIz/oZPpV3Ft+YURtcBEsWfdUbjTdfgM0tHi54p6g45nnwlrdjp/9y4OPvl/beDzPzULcuTudai6AMr+zyBl1ZgWTFGFNqbywdBXW0lv9bumzwno8wg5VD"
    encoded .= "8MbzzM45P1FvfsIP7hF77xWHDposwOat2PNfDFuOgbqG406Ai68O9pFLpQfuElNziclMIKNlqEZ40bHUYR7w6MSMxxiV6a8L4HZjx3oUg2T5X/xVs3POh3Ik"
    encoded .= "JiaNH9wtPvtx6aE9oqySSV3gNZqagZecafzaH5jNbhYz8+JtV5pd9Xbpif+GwURiTdO4oA2eEvt1iSU0j6KHJLxDrVzjbMB8qmestfxoDY7eZrz1j6CuYGLS"
    encoded .= "+Pbnxd9dJt3/HTGYhOEUWJHYaXo+vezLt4prL5b2701JceEIsfQOoxw1xlEqCull6LGs3UGojeZ+EaaxQM1UmIVv8W9QrsHZv4VNzcBgCPffKXb+rasYwPQc"
    encoded .= "jNbQUduM33+32RvOxcpR2ruwBfb9UHzsCqlaT0q87CyzE08zVldyldrgv/F+x6VjnglkcnJHCf+mtv5ROiwEIxSGhR7Pj+DIY42XnpkOGq3Dv35UsmAwgAiU"
    encoded .= "NXb2ucZJp8Mbfjuw7fhk5RhhdtF4+B6x659Qkfu+V74eq0fCMv6Vs7bnGqmlbo1DiKyAxQi1yxrorK3AyiFj5ZBYeTLR5FNPpPujdTj+1GRpMO76mumRB2Fy"
    encoded .= "Jim3eiitA1lTStcRnjwI6ytQV2JqFr5xm1h7Kpn2hacZ07MpVloqyKJ6r9jzcRZqFZDoKk+Pxsm/YEzNAcrWJ3ng0EFxxy449viu3LrnW+nZaB3mF41jjof1"
    encoded .= "VZhdzOUE8ILTYG7RqEbivjtTwB7YBz98ID3bdCRs2mIceMwZDNVUDx10AG2I7i4P5AXB4KkV+JXzjF//vcNbzsZxN1whDScT4cUIB36UmGZmDs7/a2zrttYw"
    encoded .= "xJgk+I3zm/MCN31Y2nWT5FF28LEgTpNNTKb9+xwbgBrsNwmtMXzTW49DKKvawGfrtp72T3PNHwGe6UzKlWgNM4vG1m3jGfrprq3HQRVz+dILSsvlw9g8RU0H"
    encoded .= "Zy2tN1cvE6dwjhGGE/Bv/yCtr8DkDObRkv65WDv4Y7HrJnHuRUEgGwyM+c1gJh57WHzqw+ik07GqND33RbKFI9LL77oDHXpCtraCbrsRJqegHsGmI5MhqhJW"
    encoded .= "DonCkNTWpl0950KmjZmYZpGU66BiAAf3ixuvFpJJ6uHOUjzUNTz6UGeJE15ufPt2Z3rOuP3T4vab0doKuvAD2ItfmXx98w3ie9+QZmbR1DQgY/MWbNsJ6YyD"
    encoded .= "j8PBx1ExSBr0vdOUE2EDMDoIxabmTpYuBingZufF7EKivblFY3ZBzMwn69292ynX0/GnvQbbcrQxWlW7ZjrnB0KqaoYTML8J5hZlgynZ6k9kr/lNY2Y+eeju"
    encoded .= "b6GVQ1AUifzbxqbJwDnBufvhMWC55/Bmk0Oslbst4VFEV+68xHBC/PAB8Z3/TPtnF+BNbw+sr0FVpfNlbp9bRnvvF1+6Ff3XPUq9gBlP7oNTX2W8drssdXmm"
    encoded .= "2291igk3d6WGv4V3b2qRqbSnQFtk03ZC9CrO3tVWpdm1xQTc/DFptG7UlTj1DOzciwNrKylvTEwZ994prr5I+sSHRBGA2nRwnzjlFcYfXomlxGh87ibn+3d4"
    encoded .= "ygOxFVTNQCDJY/kTnq6UKMag3gROvwlvoz8rMjENex8QN14tDYZGVYozz8H+5H3BnnNiKjWq9ZS4vIZqzTS/AEt/HHjHB7Hpedq+46SXGc850Tj0RMr0KVoT"
    encoded .= "bGjpU4cZdtAU3zHKCF3F2dUgbSHY25jayliL2QXjC7c4w8mg373EDMSJL4cXnmb20N2w9z5YexINJo2txyo87xSY39RJ0JTr216AXXpdwfvfKT18n2x2ISnd"
    encoded .= "GGysD8H7CmQIWZMDkkL9/rQTfjypSKkPn1uQ/cfOyP5HC/3On5kdeQyEQjz/FHj+Ke3pPTAa+x4Rj/8IXvxKo6pEWYqfO8q49LqBvffCSg/c5cxvNuoRuZ5Q"
    encoded .= "igUDqUsurQfkzfTCcjWqduSnHq46JdPB+X8tbMJ2f8n14B4465zA6a/Djj4OpqY7oVdX4NGHxLe+KH3xFufA43DRe4K9+vVGORJVKTZtMd714aFddWGpe7/r"
    encoded .= "zG8yYtUj/g5R4x5wTw12ynrd6KP1AB28rKeYm5mBYoVm58RoFf3L37vd9gm09eeNzVtgMAnlmjiwDw48itZWE8VOTznX/pVTFIW94nWhVWLhCOOyj0zYe95R"
    encoded .= "6u7dztyiZZoXBWxkocaYTdBk+upNjZu+YKypbpCXixUXVkXMDBYWpRDQYw9J3/0q+ubnpe9/Xdr/iFQUzvyiQ3AoZMOh+NCltb75RWdiMr27KsXcYlLihFON"
    encoded .= "tVURTC2i+1fbkXkuo7uKKc02+0HtameVeZHhErWwZpwYXVQVuDuDCWd61pmZh6kZUUykRFSWTh1FjMrdmvjgn1fa/RVnYiK9Y7SeCOK8dw6py4Z9TA3UD/NA"
    encoded .= "Ay9Pybht5cbYp72fRy4SLsyV3OA4jiyamwurJCtdVkVPH49Wu4jIXKlPiLXnzCved3Gp7309eaKZmcY6xaR5aqzlIvQwFJoxtUcdasRUM31jvPLrx0HySMaP"
    encoded .= "8niwl8WdnPajE93bSbYj87bbSvdinUoOr+Gqi0rd8YUIbjzyoHPjNRVFEZSTmIyAWzgEsAOFAbsIyfDcFYxfGhvBKP8M1DBRQ0a9TKK2uOpo1ZFt7F2bM60t"
    encoded .= "jTP/5WPrXAWXI/Hei0odvc04uD91a5MzWKxNkmSFydAeAM4ihFO25hgw3eLCEndaK2Q3QrQuO7cCNVVjV2wp93utkGq6vBTpvWE0TbXZnFHXohikTu3Rh51q"
    encoded .= "BNNTJmrkQWaJ/sw0uAXScNdSzobLlxjuf7LaXYTipLKqa7kKV3Kx5dFeO3DNEjTjvr6Fu7wxnjuSUzpOVjMPbRzbHgDK077Uo7RNcRyEqYH76O5Yzr10eQ8V"
    encoded .= "pGJO25cIVyxbae6XBIKZWTpO1r2kDxvlQVXP2p3MTeA3CTGvd+8RQH9Uqd66XgzF5E2LiFpuCm4MTdgly3usXFpKsgdIY+qlJRXXfXbqM+vV6PLJwXACM2GK"
    encoded .= "TRJ7pqvN2i4cQUyGtraG38Bi3j9P2IaAab3hyDy43KPcNDmcnaz8J5d/cvfcZ/o/8o01vc2DC84u3xUs/I1R2KgaOWl4jTcubqzcYrn38uY3A1M3kGokdpPk"
    encoded .= "pmC9zeMKNn/MEdJgMJwvopfCy8s++Z2Fqzb+VnxY1760tLNYXt4eL3hteYYZ767F2YNiOOxbvAnEJnm1AZut28z3Gzi0ezcEcP///r5GizquVlYUn5OXV+68"
    encoded .= "c+HLS+wsltn+zD90b/QEwAVnrp8cCztDcHx0n4YOu+lXGbWZUXJrneEBx7Hm94kEMIyAvKeVNzPXnlChWDUPD6iovrK8e2HPRpn+V9eOHQo70DMMRf7/LiH7"
    encoded .= "aXI88+AnXzt2KORk96yuXc92I/DaL+BXYP7T1vwPjwtoXN8qVC0AAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERSAAAAQAAAAEAIBgAAAKppcd4AABdtSURB"
    encoded .= "VHic7VtrsCVnVV3r6+5zzn3OI5PJJCGTBEJCJkWCRBAhElOxFCMELL1DqQFRRIyKChIxJXgziArFK6goRErBssSaUahE8FFKkgEiigkBQiKJIZGQTJj3zJ07"
    encoded .= "955zur+9/PE9us88gpbxh6Wn6tS9t0+f7m/vvfbaa+/+LvB//MX/2umiFsEbAPekreD2J+1KwHfDtm2DAOpJvCqwuCi3fbuKJ/Wi/4Ov7QsqFhf1nwpS+cQf"
    encoded .= "i9u3w23dSg8Af7yoAa2+qG7chb62jfLoGwxmgOQkGSknLwhmTnIyAPIIFzDIGyAZ5RxhBpMzeqPo5D0I5yBvdA7wHgIA58L1fTxu4VoAHLxMBMZl4fY0Zvf3"
    encoded .= "p6p7tn6EQwBYWFCxYwfsiRBx0hSQRDJ88Y/ePHy688XPCHypDE+rygIKhsEU3rLw7v4NAMHg8Hf6Pb3Mh2NIxwhYvEZYRDifLvw0CwsW2utI8ZiA2gTCHiJ5"
    encoded .= "C6z+wNt2DO4PlxF5Eiec0AGLi3LbttEWF1WeW4/fArpfrlw5M6qBuh57LxlBmXWNEEzMC7VomLdwFymci2SAAV7RyPg3mL6vaBwhH9fNZDpTgI5ZvgjQlUVV"
    encoded .= "VCUwrm1FwI0H1rsbbrqJdbLpWzognfjBNyxt6A0G26f71RVLy2OZoQbgzOSUDBXgGwVjQZgJEmNKtNFMETJro+YtoriLoGiT4vUUvUMwopiT0Ud77XSEoAEw"
    encoded .= "EuWgV7lh7T/tbXXh3R+f23MiJ0w4QBJvuAE8D5itR/Wt/V516dGV0UhgKQNlypDNRgrwPsIcgIzZcFkHrp1IG9rv53c8zrgsMkS5mzLJxOOPTXqFZAJdM6iq"
    encoded .= "fm3+i8OmuGLtzVi6AVA3HSaYcsdWuG3baMOV8YenetWly0dHIzNWMtBSDsef3hAhT5gRJsbjiimgbLwJqA1oDPCM301OigYkNAR0KTqGIS3AwAti/oK63BGd"
    encoded .= "JjFf0wSaUK3W41FVFM8qWX9kG2hbFyZtzgjYvl3F1q30H7pu9IrpQe9PjqyOxhBLM7UEBkKmDryZoesjH4TFtykS6QHeI0YVrXGdCHdQjAx/MCMnfxZXnHiC"
    encoded .= "DA5j/MAkOMeIimxkPaiq/mo9/on33Nz/8PYFFVt3hMIULycKwI7XY3CoqO+rSnf2qPbeTA5izvMMYaXIBgdk5laH9RVILhlonTRJ0WSErtANZgBoPiYFHgmw"
    encoded .= "hjp/H++5TkYnsJhAwkqWzsseXbbywps+gdV4UhALi4soCGq/G/1Av6rOGde+MQ9nTYicRWJLjJ9Y3rxgCfJe8BEZjbXGp+9ZhKcZMiyENk268LacAsnJjPeK"
    encoded .= "NIdUdtXhEna+E6+RqwlcY42vinLzFMYvAajFy1EAkQMuui8CT+6HZFDjIfNhsd538jU5Ir/D4jIn+E4qdM7zPh7zrT4IxEd4ixziY+pYItKQejmH1CW/VAqP"
    encoded .= "TyMhpBqTQ9PXA/EJ4A8DwH0bU7KF+qnFRZWbDtf3OleeP27qgABLF4+lrRvpGLWU/41HLmG5IihwxrHCBhHOlhJVkftzfmf8x69F8mAyXq1uSKWSrT4gGUWV"
    encoded .= "uplhpeuVXvWDq2dUW266iTUgusXF8PGpR7HBpNPrpoH3onlFY0J0vAe8lFNAPtxg3AiND1BOSDEB5iNhpvsnfydii/Y4Eq5AeDvAMUbQtUYxe6eNeHCyctZ3"
    encoded .= "0ymlBWPJjEhi4xvIdNr0XmwAgEWAbS/gh7MmDswgs24pOqasxcgaBG8t26fIKSu/FHZm2CMbFhzoG6CpAWsSMoIjihIoKwAFIM8cRVkURVn/BgSQKT0S7Str"
    encoded .= "j1R5wqcmElNOmAPwOBaPaYZC5JC/nI/FfDW11cBbrLlRoXaFTZt7k0LTOaAeA6NVoCyB9acC608j5tcDZS84Y2m/sH83cHAPMK6B3lRwhppOBkRbFXNNLtTb"
    encoded .= "lP9Auw5F2lSEoQz0NsoLO84BGUIeWYDIa6K+N8eUOk6oOuY8TGgoikCERw4Bp5wGfNeLiYu+AzzjXGJmXp0VBJivHAF2PQzd8znhrtuEfd8EpmZDfTc71sqA"
    encoded .= "DMdkcFDNMoGOYEQJrE2npm6LZ3bAaNTyTmTNCURYhHsqdV09kPK/9TzzHQoHDFdCxK+6hnjhS4m5dSEeBqEed0iPgnPAYAY472LyvIuJKxeoW3cYbv04UQvo"
    encoded .= "D0LKJDQkjmkTLvYfLshpiycw6g0AKA0nRgA6jYykrOuTxOxG/jitj/bv1KCUBbCyDGw8k7jmOuKcC8OSx8N48x5Q9XDcywwYD8NF59eDL3utw0XPgz7y24YD"
    encoded .= "e4GpGcH7TnoljmAk1niwXZfyh6LUsO0FsgMaTzp0UqBTzpoUoVQBkl5PRjMxrjI6XTT+nAuIn9pGzq8TxqOw0N4gxGrlCLD7EeHQXmg8Anp9YO2p4KZziKmZ"
    encoded .= "sMbxKBjz9EvI17/X4f1vMu1+jOjPhNKbqnvuJNHhhmMckQ3qdAMTCPANcq5n5p9ARXKA2nRJyOnUYueA0QqwaTP5mrcCc2uD8a4AypLY/YjwT5+UHrhLOLg/"
    encoded .= "kF9aJB20fgNwwXOAy64GT31K+Hw8Ek45nbj2t8l3vU46ekQoei30U4U1U5bSEwiBIimL1tHM2Rdl0Vdme2slbe3VtqvdqyaU5JqLtkL4AO0fvx6YWxuiWETj"
    encoded .= "P/0xwweukz73SeHIoZDTc+uAuXXE7JqAjkP7hZ0fE97zOumzNwNlFbTCeCSceibxY290qMdtHyKkNXbCnqCRAhUrQhgpjLIZ2QFHV0bMraQBTWx1FSXlRFp0"
    encoded .= "CJCubUrIEP2VI8D3/ajDmU9FjnxREh9/v+GWD4ZVTc8DLAATtXQQWDogHFkK1yxKYHZdCMRH3y194kNCWRJ0QD0WLn4+8NwrgaNHwrVTScyEDFAd1HY1jQQU"
    encoded .= "TV/HOSAZkXv0jvCJA5oohbu1vtXn6ZzRCnDGZuCyq8XUApcl8fd/Kt1xi7Tu1HBe3QQR2zTilVsdXnE9ueXZoWIIYdJUFMD8KcBff0T67C1CVeX78UXXOA4G"
    encoded .= "MW1x/Ks1HhNNYivQjnEAe/3QhHWbnabTzSXDU7JF0ktpkF6jIfC8qxwGUyF3qx7x8FegW7cb5tYRozqkFh1xdAl8/lXEi14JXvJdwKsWHTedBQyHyGJLImbW"
    encoded .= "AH/1h9C+xwJR1mPhzKcCWy4lVpfbcaEiP5lvUyLNL9B9n8gBjR/S4uTHog7ILN8SFJxrf6djlrZEcNLMPPDM7wx1viiCAz/1UQNIWGJptsg687zQ+a0eDXDe"
    encoded .= "uJloxoiT4NBulyWwfFi4/S/CStJw9VkvDLMKHsP+KdLZZqFt20/mAIwGubPLTU2nztc1MR4So2EQL+NhkLSjlRB1IeT76WcTp54J1HUgr0f/DXro3kBuFlPC"
    encoded .= "GsDXASH1SHQu5jLidUfhp0Ul6T0wmAbuuQM4epio+uHcc7eAUzOAr6Es/yMXJVSESpbrICR1KLBTBksHjRsqta9hHE00Y6IogFM3pXxijnhqNEzA3l0hf898"
    encoded .= "GuGcUI8AVMADdwt1DVRTgBpgeBRYs44oKoBO2ZiUpnPrgA2nE3NzwtJB4MjhYHxRAQf3Ct94AHjGcwDvhXUbgbUbiP17jVURnUBF4U+AsSQmvsqCYXS8Axob"
    encoded .= "UiiQVSmJegzMrwNedb3D6eeKsrZNTWJKCGnx4BehG98orDkFHYuExx8S4MJ59ZB60TXk816U5mEhmt4H5vde+MGfBV/22sgRh6k/f7fwr18QpucCCnc/Qj3j"
    encoded .= "OaJvgKkZYn4tsGcXUJVd4tZxwoi0KJkJoH+CFABCTYqNEBgi+oIXg2c/QyRDV+aKELnEhQTgG+KCS8mLn8/sbUYDlw8FpIxWgdOfBl75cnFmDTCYBaZmg+Fd"
    encoded .= "CJQVUA0AVwLrN4E/8GrCkbnZX1nqLjggSCHotCD5c2vcEmA7LpNEO1k3mBaStDwY5CpAVL0TFZt2IQBwaD+wuZ1+AAjNTWQ+mc9XRxFdb4gOj6+imPy5sgw0"
    encoded .= "XlSEcFF21xG7w2Qs2ulwO4KOK8ldIeR8qwPaFKgHEsYTkrc/BXz2E9D604znbgmzO0gQKCmmBCjvxS/shO6/W7jw0nTDsMA1G0LZml0LPPY14eY/hF7wYgIM"
    encoded .= "35+ZD/eRwnTowB5odVksSuDAbuFj70d+NkgAazcGJzonNLWwvAS4OBcJ99WE7ZFHo/ti2p4IAb4a0o1dJjUzgAyM/9H3QlUv3CPU1+j2SDS+CYd6U8Ceb0QY"
    encoded .= "xZuds4X4p78zmIHVALjtL4R//Guh6tOOHBRf8SsO336lOBoC5QDY8T7hztulmTUhBauC6vWJeiwOZoCzLwy3Livi4F7o8F6oCGow8D+VVWq7ktgHpEbNnUAJ"
    encoded .= "Fm6Q1GIHNiHnp+YS8cW5XZnkreCKUOKmZoP+f+RBYfWoYpsrXPhccH494evAyDMzEA1qhkIzDkjKiE4zhfjn1AAqeiIojpep8y8mTtucOkTg6w8Ylw4KRRXk"
    encoded .= "L6LUbZ84qRVrSYAAaByOd4BfHdI88iQjpbIUBpypuUhAah9MBIHh60Bge3cBD32Fci7ogzUbgOd9P7F8OJBn40UQZAE6pger8XoOqkdRcDFq+rhwR/B7X5Gf"
    encoded .= "pQAA7v4M1EhhXGpR+qijfDuPysIDleAM14yC3dsmqsBgYtKUmx10y0vb+OQpbDoQy6L3wmc/EWoQwyYHXLmVPOcCYnmJcGU7qS164mdugQ7sJnp94Mt3AA98"
    encoded .= "WZiaCjKYCEOVpT3C911DPO2SEP3+ADi4D7rzNsPUNCYep3cRlPVPtiukx2jcWn3MRKjzpYgYdWGpFP14LHVcyeUmTM0Cd33G8MCXCpx/CTAaCv1p4sff7PC7"
    encoded .= "bzQc3AfMrgmqsOwRX79feNfPS/PrgEcfDjcqq7grxIhDu4XLX0q+5DVCU0clacTNf2Q4cgCaXgPmx25s15+DkwKp5AnCDU7SDaai0Z2xpSl0ys9jEZJugo63"
    encoded .= "BeDPb5TGQ6KsYh//FPHn3+mw+Tzg0L5AriQwPRs0wq5/B6YGwGAAOEHDJWi4JLzk1Q6vfEt6OBuaqyMHhc9/ysBKjNCOaQDBS7n+J95vNcDJu8GutelBZ0ZE"
    encoded .= "p3lJDkhp0XWKEKrHYAZ4+AHDh98hFUWQ0uMRsPEs8RdvJK9+NTEzH+YGSweCPPYNsLwELB8CrCa2fDv4S+8jX3at2DSt4mxqYc0pxC++veDUDDBcDTI+IoAT"
    encoded .= "D/+TDfnXGM3RCaQwAHgvpiGIOla1ZTFOXFsqQNcLkTPka3BmHrjjbwy9gdOr3kQWpTAahkrx/a90fOHLhAe/TH39q8LhfcEBU3PE6WcB5z4T7qynh4uPhlEt"
    encoded .= "xkDQAXUtXPBtxK/cWPJdr2+0vCT2pgGrkSrhxFxQ1kV1Zzgw6YAhSNeOjgwTyHZs8yM3FxEeSYfEeSIdw1xhdq34qb80LB1w+snrydm1YfH1KHDFJZeJl1zW"
    encoded .= "TbjWm+NRcHR/kBYdOSC25OOR8NSLiF/9vZLv+IVaB/cLU9PhaRUUlaFzmRRCZ6mJgAHdMujJnNsd47OGZvvIOfXXiXN9SgmFWb8MgBfUQPPrgTt3Gt7606a7"
    encoded .= "doapTn+K7VOiYYhyeteRoXt9ouoRX/5n4K0/afqX20J77ZvweVEGJ2w+n/i1P6iw7pQ4InPx2QVa/d/6N474Os1QK4ULiQ1zXc6Gp+havEAHF7lUCvKRiARC"
    encoded .= "FLxEB0qNNDtHHHhc+J03QRdeKl52FfGMZ4PrTwMqNwlL74FvfkP46hegz/2d4at3Q00tPPhmwxveWfBZzyfGI6EoWyeccS75lg/29JvXjrF7lzAzF66DCZ6K"
    encoded .= "OD0GAdkB/eEAY4xzI9SNfhYEyZHq/Azn0CUNZYKRBB2SMJEPyrDqA1+9G7j388L8emjTWcT6jcBgPpx39BCw75vAnseA5YNSUYZZAAbCcCy857pG17235DOf"
    encoded .= "e4wTxsKms8m33NTD21470q5HhNk1ES2Rt1xUypJQ8yQk2O7F60AnD9y6qGg90c4JkcdQyd+phBhEGkUK0zMhBvWIeOg+8f4vpQVCzoWKUfWA2bUxpeJzyV4F"
    encoded .= "jcbiu95Q603vq7jl0o4TiuCEjU8hfv1DffzGa0bY9Q1hMNPuM1TuCoDeieYBIwyRhqJpFJ4rQTKpU/eDM1rlFXzF8I4iXHDwAuOjNXoTmtpQNyJp6A+k2Xlo"
    encoded .= "fh6anRemZ4X+IAwvrDH4xmASPMXGxKoPNI3w9l8Y6/4vCr1+hxPic4MNpzte//s9zs4r9B8u0HRu8UF0hGDnwYilHQjInkpDjbBHqE2DhI60bSY3T0h6QTSB"
    encoded .= "jcQWMalRCWxqZvBesCZuvvBBRjdm9Cbkd2MZBU0T0FGPgN963VhfuxeacEIJjEeGTZsdnn1ZgZUjghMlKSAhVbgTPRhJhnWZM/9trYVdfiBaZZXPS/VXbUoI"
    encoded .= "goeCY2g0iB6gJ+gpeho9RA+jl4UJrqKwcYG3QnUyWG3oDYThUeFtPzPEw/9q6PUZNlrkET3lPfOa6CEozDuddJIUoI3M1KRpX0uCyrU/bU7MA9E0Oo8eM4Vt"
    encoded .= "NJYkKASZZVGSUCAwE1LYWCmYGdKeJAHwENNn3fm+IUR8MAUsHwF+49qxvv6A0B+4WGIdHn3IcOdOj5npsJ85VKZwU4n12K3mLCDSJqkXa/qgH/8bXXWG97U3"
    encoded .= "A4PxaTNku7jc+1gyntFJqWiilZ0x78RWl3clJEUZ07PrmHrxp3X7j3Bum54CClJHjxrnNxA/8nMVNj/d4dGvee74QKN9jwO9KYE+pgCgoqhKgz3erEydv+M+"
    encoded .= "LgOhdOcN0q+7avSpquhdMa7HjRmKZJx1UsByxBGFhbJTLEW9ncy1lUJqjSXTBsbca7SkG67PBPs2UvmcdHvGKfVoJIxXQ6kdj4DeILTXKZVpkAhflbOVt5Vb"
    encoded .= "/+yume9ZhNw20EIK3B5TwfGTjhObKdpeG5gYNQGTZa8NVrcnbWUTDcqcIIV9TOk0n3K8fYjZbcjSbN+63ZyFVPNRY8yuJXp9Ym4N0esB9JCzyNGxMrlQyv4W"
    encoded .= "AG6/HK0EUzzluqt1xqhu7jfDlJnBJKZ/Uki7N9uughnySCKoWzoTBCaIs/Ved3+vUoXJW2s08b3cZWnymm1pQxxPKu9LCpcL13OCXNj1O2wMF+z40sxjyebo"
    encoded .= "BWphQcU7b+Eub/hgvyoLQR4Idb0lROQhiEnxIQpzWiQyzMPTDgJyqVR3R5la4ksbMixVgTjP6+xPaM9LKIkEa1DeNpvWlDZRe0impqimC4M+sONLM48tLKhg"
    encoded .= "Z0SChIIbFsHhHZg76povgMVTGz+uTSwyNFNkspmciGwuoR0WyKBRu2NUXa+o7SSjWs1plZ88dwigO5Zrz2yhwLDvG3kZQFMUg55X/ZCK0bO33LXuyLacWN3H"
    encoded .= "4/HAO/6Bh2V6uZmtEmVFoGlvwjanJ/rqJIUzt7cIkPIOcgYxEAVWpyROXCU58vh/jHDCMdqzQ4pGyQclCzE8bBFq56oeoBXf4OU77lp/ON4pX3lCCG3bRltY"
    encoded .= "UPH+f+jdKauvJrBUul4PQBORHmUlIym2pTEzc8pVYSLScY1hytshu/bdDl6ch5TIJyY6DTKEEVhLsh0AODDvF4YMDo0rpvuEO2xYufovvzJz58KCim14gn+Z"
    encoded .= "Sa/w72b0r71i+RLnBjeVrnhu7YHaRk3QOwzSKsIyy+SYJrI0JEmrO5YH2pRJSIgcGKY3Kd1yh5lSrr2W2luG46RokgzOVf2qKnqom+Hnza/+1I571t+TbDrW"
    encoded .= "1hM6oOuEyy+/rbzQveA1Bl4LFM8sXCK9aEzadBBXoonIT6Q6pA5C4nGb8EyOYOu4/HkUSjnNJlOGdHACvI0A4iuE/4Ndaz5/086dVzQnM/4JHQC0Aik5ZN2+"
    encoded .= "+gXy+G5P2wLhFJMVgAuJJyeL+1GTcuxUQsiSvkgWBGyHh2zGmI3hAM0l4Zh2ekZPUgbl3b+C4tb7BnT7CXcvDJ/evf6f/3HnzisaAEiC54ns/BYvcWHhf8+/"
    encoded .= "zaZXWLOeMMDAt0DA5EtcWIDbsge8byO0ZQuEbf+dJT65r/sWwD17wI07oR144n+X/f9X5/UfXnVkjKst6OUAAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERS"
    encoded .= "AAAAgAAAAIAIBgAAAMM+YcsAAEbeSURBVHic7b15nGVXXS/6/a19zqmhq6qnzCHMBAxjEmUIQsLD+FAQROwIz+t01Q9CABVB/eDQ5F4UuSAOiChw4fIEhDTC"
    encoded .= "BdEHD4QE1IAxzAkBgSQQQuiEdKe7uqvqnL3X9/3xW7/f+u1TpzppwPuen5eVVNepffZew2+e1trAXe270Cj6c1e7q93V7mp3tbvaf5j2/4LeUl3J43giTpJT"
    encoded .= "12f1c6xFTT///70mxwOa73y0f8/OScq+i5CuPgvywAeCe/Ygi/yvXeB/tEZQ9u1Buno/5JqTwEv3Icu/I1EMvvtdUi69FAn7ABHpAHS9b0l55fMx3w5uHZya"
    encoded .= "T8iHlvYLbgFWFk7yRX4TAHAzFtZOEQAYtsgAsLoNzAlpYQ2ytgACNwM4Batr+wshn4QTAeh3ta0cBg8tQ1bXICcCuGH9VlncEMH2Li8dOomrGxCcuB9Lh07i"
    encoded .= "6gpk6ZA+r9drP4vryjBHD4NLc9DnsB9Lc/3ndPbA0kZlsKU5cHUFgluA1TlwqfS9eghcWgR3zaG7bRcmcolk7KswEwB79rDZA+CifcjfbQnxXZMABGXfpUgX"
    encoded .= "XSQ++bf85sGdG822s0F+X9fhoQTv0XWyHZlLJIYAMkSEIJB1YZkASJBCEIkECCUAAgSZAJGcQYIgBMwQ0icCCJgzQBKggCABEQCSASQIQKaOyASJDAEFIiCp"
    encoded .= "mqXTvkQgilUSgEgSnUcmyMyCDWESCKQMSR2bgCSDMIUZEJAQCCkQZgqJDIIAWmmwJpDbRHAjKVcj8eMbsvbJV/71yq0G00v3sPluEsJ3hQB0Uor4N+7lPNrx"
    encoded .= "j6Brnp6Rzxs0w1MGDZAz0GWgbQFmFCQrvvynfCDLPeWafidF6RM515mTUrBRJkOgK33489nQL34Py/iZdVwJczHw6Pgs1AcIdB6GZJR5iQCS9OHcFUK2aUqd"
    encoded .= "i43vcyufU9L7UvisMGtvEchHpcG+29pvvffP9528Og3z76R9RwRAUl78Ysgll0h+/QtvWR4Od/48gWcOUvMAEWA8yei6ts25wEPZSQBBJiVnRQ6l/CYhIiTF"
    encoded .= "CEQKkIp0oICJJAUJEAi7rKxl2KsEU3+EwvJPJbz4EwFShIaIzbMQS7b7AjZFagcilb4ykSFEpkiSQFgEO5UoScqiKEASiq4P5TILUaUkzWA4SIAAXe6+jIzX"
    encoded .= "tIPVN/zBW3ccICgv3qvw/3Zx+G0TQKTA//GbG89Ak/7L3HBw3/V1oG3HE0kAgYQMRbTzjyAXJCBwIFnkJ1g+l4FYuSkDZGcyGYAIcuYULko/igRFSqE+G1e0"
    encoded .= "r6JuKihMKkAESYqcNylAW0HBjhGOczEhUsFJv0Gi4CmExCqRTPJsIdBFiTGTQJOGw2ECJrn9KiCX/P6+wRsAtRH2fZvS4NsigL17ObjkEmlf86Ijpy+m4Z80"
    encoded .= "afi0riXadjLOGYmqp9XhKwozG5ckAbsKzC4TudOpMCAkU4Gvf6BwAItqEAd8VwBYYFm5eoonqpRBNSoMAlFyZCVGcWdVqpQIWHLCMOp0K0PqHSLK9YQSR+xH"
    encoded .= "KpH7E1OExAIkCdoPRG6a4WjQAOOue2+bx8/5w3cu3rD3fA4uuVza48XlcROAIf91Lzj66NFo9NfDUXPG2vp4wgxhRiqwKNxUST9nAkkcQXa9y3AdbiJRuUcK"
    encoded .= "0RDCyukwAZCVLTJnxwlyjhCsiHe9X1Yfr2/6257NhWCNSBAkQS5fqGmnSlwMuNIjymnA59JTsjkbQVQa6v9dL2cSeX44HLVdd3NH/h8vf+fww98OERwXARjy"
    encoded .= "X/vrRy8aDUZvAtJ8207GIhgw1wUUcx3MEogBzqaR28xaZwB6RSIdiLkziFQiqkQToVPEdhnXxJCJ7YwyJkIgiaGLHPou3MeeuCgMXJSaXYtIisakiffeOFMR"
    encoded .= "rIhvoyfx54NqEVuPL7Vt0mAkkictuv/8ir+Ze/PxEsGdJoC9ez88uOSSx7Wv+/X1HxsOBvu6nMHMDkRjVB71NaDi2nS8cYxxEyCbkB9VgIpscYSaMSb+uSC4"
    encoded .= "9OWEQCKJOKJNx5qCnEU4USL1vIcAIfMkeqLcCSuwasB0sSR7Y7Csre/EVYPQiKtKEWt9W8Lnq6GRNBwO0rgb/+Qr3jn31uMhgjtFAGbwve7X1i4YjgYfyBmS"
    encoded .= "cyaJlGm6DtVSLojIm1w5BAlQOJOVo3M2mrfnlOKt3yhVKgDq72h4EUoAqViBZvC524egn21u5ZkK5CKipdonUpScE2zp313NMB+lB3H1guzTU7vFQVVUSJmI"
    encoded .= "2T51PXUdLoUi8gQ5iaBJ0mzkyQ+98p0L77+zhmG6oxv27mW6aB/y63/t6D0Gw8HbQDRd15FAcv/YEIv6OUdRGrhKffSCRCdpuvGlul5/LL5DALkrxGAAi5xq"
    encoded .= "42dBR/0xMZ8BdEVqdEUi5RI7APrIN8KpRqTOr66l+mhq3wj8XzFjURz51ago83NO6M9dRFC8ps3IZ7Sb+jZFYKzUkeg6cIjhm1/wo2v32bdPur17eYf4vQMJ"
    encoded .= "QLl0D9LVZ4GnHdn48OLC3GM31sdjEgNDBE2moVIzjWsLexlA3S6LbFA43zjbQ36+QJaLJnoLEsKYEaBtLosK7AGop+GGXg5KOOBI1VKUzeK32QePDMYxWPvO"
    encoded .= "GRCyhgBJ0Mz4rs5fpMYHVFIo3Hoqo9JOUT/1u+JI9JqQ3dxoNBy37T/fMBw8FgD23UHU8JgUcumlSBftk+5uaxvPWZ6fe+za0Y0xiUEUo2a158K1zMWfTghW"
    encoded .= "vzi8ehZ7Lpxt1jYqR+biHbi/ZgSRpac2mA1QotKlGJb1hx6Zq5yrYlZcoFRfv4dbx0K9Tkehfu82jOts9n3SECByPERRGT5KHSTQViE87yP8njI8kaRZn0zG"
    encoded .= "c8PBeWeMN3513z7pLt1zbBxvKQH27mV68YvBv3j+0dNGo+HnBGm57TpAvTJtUTQW8e7cUGbtvndZSA7i1RDt35Zns/dj7mE/MGT3dqxEAxHkTu2OaIsZgCNq"
    encoded .= "BepHIYzpAsk7hBK3mFCOHgyDiK/zJ4gEC2gV/nafPoSrHTxmW4QvnNPNrqLf2xsyDAECKVFIITMpkgDBkQEGD33Zu3HD3mNEC7ekjgc+ECIibIaDF80Phzu6"
    encoded .= "nDsJcitrJsWJ2RCbO/3NDA34FJ1uHOm63hCM+qwTRJCxFtmruo895JuGMIRaRLCvRvp/5zIH06/WnNCcEI21S0I2zsvC1TavTF+XU5Nivj8PY93IKHbNPIwc"
    encoded .= "jM7yn+HcBYdEBiG6rLRCQHLO3dxgsDJB+7uA8Jprtmb0mQSwdy/TRRdJ9/oXHjlNkH5qbaPNBBtHWO67eC5ae4Dvi+kK+AowD8VGQphCHAtiXNqYqEe9B0ZY"
    encoded .= "FZN9xLLaHx7SDW6WRGQ5nvsmfY59VvOlSiqgEDrr9eC+wuYZAV1USP3bfrH/XUB2XJOrW9a1QYAk0qxP2kzyouc/5egZxzIIt5IA6uyw+en54WA559yiJGaU"
    encoded .= "w8U53IhBOUb6Ii8LcuGKvldQpEeuET6XGix6u7cwoC1c3xkQwu9NBFe+trF7nGMER8IiLrHLynEsIdjNljd6v40drSNx26NaeGGQXBEbpVAdw6RDUDnOZH1i"
    encoded .= "s04rXaokyQLJme1oMNzWcfDTAIDLZuN6pmiwLNOphzc+OWxGD5m0k1ZEUkZBSme6u6Z4CKAz7JjfTnHRTP+nLsrFvQAW+nVOLgqvDXkDEG5sqdfQTwMbpwPi"
    encoded .= "KWf9s4hrwuPzBrBq0AHBktNnTRf75KsvHrm/3hPH1LGQrG/jbPHxop9vQSMxNIVpuVqzz+G5XuzBbxQAyI0MBl3XXnv09OFDXvtatBWKtW2iCu5lEghPPjx+"
    encoded .= "aJLBA8eTcSaRcmbV6WGOVZ/rtZwDEtDnGgNUNeoEpk8tO5dp4q+KTrMt3CEwSz4QkoeVi3SSqnR97JgZ1LkWKWWeBUxymUSxhA/6IeLKfHAREsBqUiQS/cxW"
    encoded .= "CNIhEdlx2sUTIBXV07NHnLgwXReRuq7tUkr33/aNybmAcM+ezWpg04UXm/jPvHBu2DQQaR3QKIiYFv1dNf6iBWsTNELImQpsm2j4MYR3FLRUPd8FnZmphmTX"
    encoded .= "lUxhhotWMgSYAgHBJEpQnvTBiqqSeF+dxxROp2yauna1G+jjOuH7OAGJDNcLxo0e3aAPRKYExF7GMRKwqY/MGIKv84egGw0bIfC/AcBZ+zdL/E01gddc48Ln"
    encoded .= "kSWPL1W0Bu62xVQhWoyVwl20m0X1ngeCWG/OlhEzqdCvwKn+tI1ZhHaQOD2dbCqhANTUcJXCRbf34KBBG8/4RePPHMAUx6g2jtgt9nsqFmzTl4LZiMcaEqAz"
    encoded .= "ifXj3WSDaVmMmJg3hPfFixGzrwsimYBIejgAXHPSZnk00wbYu5fp5MMbnxnI3APbdqPNRHIRmS3SZ4hD0K0qHZTAlRtz4VQ3/OIcg74nxbnbdbaYOO8/58gv"
    encoded .= "xOWgYG/9DlCyYinCqKQenEBQh1YHNFXw5C6s1SAXidnsvOmcblDeNYRtbmK1b6qQkqlHowgpcDY1VS9X5DMMDeRBGg0yJl/ccXj4QE0Q9VNRPQlAUkSEJ6+u"
    encoded .= "nkCOTm9zi+xlWdX1C7OtojSKLkoPyDTqNQ6lmHut6qNM3qJ1zvHFSMyoPrcRk668Sg8Hh0kOg0y9WJHEQKQZPhcHt9g49XFDVYr39lmujxEExAbDTcFHFxhu"
    encoded .= "lrnAiUwaimQkEq/mDmDZVMef3uAEmiEZLSTx5CPbjpwA4OYq17T1bIAXv1i/GzZLu0Esd7kjKb3QqutK+9sAlFl0fCWELsLGCKNXJFJ0faceRF2I1H4MYTYO"
    encoded .= "0euDQI/4eoiI1yKgWcy0nmFVIn7B4LOHFf6xSigQiqHFGV38XjU1goJHoJ4Z03L1Yl9Eogx/xybhtxGVEZk+25HEctsMdwPAi/f2e+kRwANLxGhj4+hKkqYB"
    encoded .= "kOnluILNsLSqHBZfv0LeOT08UOi+WPzSK/tS8dkXex7XN+amcU+f68yOVukhlbsSag4/iMgIgho5rNa4C5MgBep1CWNWOFhfprONePW5GlsAahjZJKWUGkR7"
    encoded .= "vnK+2isSqoyqERonZtOvpARIAYV0gzRKyLILAKajgjM3hjQyHACpz22lf19UqIit3JccSYwT2QRseKAnCdBRevjpgbcyV/93rIwpN4mpB3Ot2O/KS7fKEAbw"
    encoded .= "JjKxkbsjgg742k9fUAfw1M+ZPcILpnK/biQDSGZDlYwgp3vVTrz62ceiaztXmySkQW/9FIADu9pvMwkgJ9iWiYrQ7IaoSdHqdtk19L4sqV3zTaUQC929Uw6o"
    encoded .= "mq1Ki2DpB+4X0eQMcjUWjcOMRcWww+q5iAED1TzoWqCd6G+zNVJTAQwAXZeRs3JnMwQGI2BQIKbqL4j6OCAMobE7qTRbFuZrzJVode1RRKFPdIEIomfhKkqK"
    encoded .= "lLRCFZNiW5SGzCaALkoUSzjAAynVCrfFx6yW+cE64+kqn8wpVcLqc4uphXLBmY5m01SYOMcEq9nD0HZP+cNE6GRDMF7Xv5dXgLvdQ3DiPYCdJwl27Aa2rQCD"
    encoded .= "kY7aToAjhwSHDgC3fRPY/7Us+78OHj4AMAtG84LBXPFsAnCjzSEC92AAls/90G/FZeV0SLV5euvtGd/1eeufsWYsiLOeHTTVZhIAuzYpqQuZKy24ZVxI16pi"
    encoded .= "FNGKIQlyt/rNypltmXRCrej1ueUqyu3HuAgF0bZiLxcPwZyeJCxjp0a5++hh5YiTTxOceY7gzLMhZ9wP2HFC4fpNbYa1hQYHbqF87d/AL/wrce0niP1fV0TN"
    encoded .= "LSgR5jC4uZCkISZQg5gdUTnJHo0OjBNBec6ZoAyUUpEyZksF5gS0NtLcxZwnM8lgi82hA426+fwK9bkbqFPscSjhOY+c+2KsCxErEMgS1Ysi1lVLXASDCIvN"
    encoded .= "7wkiP5iz5qodPazbrM46J+FRPwS5/7nChaWqRbsOmEwqAmJWcLqlJNh5omDniZCHnCc4ugpce2XGFX8PfuFTura5bdCgV5xqjM9LPw7hut3/0k8x9h+WDIsj"
    encoded .= "uG1RKELnzk1SM+vWSyXOZrp+SNvWu4OtM4EnmnWHVUW0uYPVyBF3BXvSyBDG+swmZE/f6wZjEfM04ETLXPyaXWwaYLIBTNaBB5wtuPDpwJnnKMtlEJNxeTYJ"
    encoded .= "RKj78KYh7SqlXgKIbmJzFMwvEec8LuGcxwk+/y8d3vcW4tpPAPNLgsFIbQuty4gSS4FniqraBFNDRgL33ahVokZvoeoY/SxgEIlVnKQ8uPME4CH1XCxrBJ1k"
    encoded .= "1nHw96udYL8rkjqfeF1sDp8thy1Aj1AMKBSpIeVgEDkMCmAJ5dLV24ndJwNPeX7COY9TELeTEvhJkOQu1QwW6y/Rm4QPynwEW2CSCRHK9zxc8D0PT/yn9xDv"
    encoded .= "fRNx4ACwuFSih66euGlIX4svTUzZ1QED4zjn+7IrwHJRKdGu8JaB1G0aHcAxJIAhPPesUgsD2wQQQsLiiIiZ2CiSNnE8K+K9YKOsuxoygSULcffmGcY5fJA4"
    encoded .= "93zBjz9HsH03pJ0UJSGsETz2u4yTrEHSKpp7w0n/cypxhslYS7Ie/WTBmecCb/3DzM9fJdi2ogxQZchMJgzrqNgThLVKDVeL/9Nv0/aEETHLSrLMtgFmFgl0"
    encoded .= "bKUEcdyaswyYlW2bvKZY2RZgBQ6pEEYs8vAfBDXgTFELN8RWHLJvldNR1YhJKNHf46PAU34+4ef3imzfTZlsEJKAlNh/PohdsoSiPfJXb9S5C2Oms6/cK+LM"
    encoded .= "kJyMiRNPF/zyKxpcuAdYPWi6SiDRH5DC5+63WX+s6wtzrNOyzCOcCWu8wvow4o2xGKBLg+ORAIM6KdYBaCLbmxVYxvo5Mx6lx/G9enebJ+C7ZXUxKuLEagpM"
    encoded .= "7JVp9OsdlANzyf//9G+IfO/jVdxDBL31BtUBKsJTEgwGlaf61CEB7JVi2hZgV/fvu31SbksN0I4BaSBPe07Cyu6Md/w5ubBco5OOb4nVtTa681spRq2Sz2se"
    encoded .= "7X5XC/BMptsNgcgz1S5qcnvnbYAWQFMGlSi2baXBiLOat1jda0ZbNfzU7evFEaRyv4k+RUdVObZZIkpv0/8pQbpOmFvi534ryYPPI8ZjXSx7yKuEkDvBcASY"
    encoded .= "53frTYKvf4Vy81eIA7eAR24nxutAavS+hWVg50nEqfdKOOP+gl0nVRhNxiyGJBBpRxpddzsRXPiMBil1su/PwIUViAtqRkTWxJCbCX1V35NOfUFFZ4z4LAU1"
    encoded .= "w1YIZKt9Yj0C2Fd+p3ErlEGf650QajpSbTMTZUU9iCLfRHoOz9eTPWJqlL3VWurBVIFYlMz0sxEPgckG5ad/I+HB5wHjDSCV1UTjUETHHQwFDYSHDxBXX0H5"
    encoded .= "3EfJm64HjqwqV0uJAqZiIHZZr7ctKMjYvgu4230FD/p+wYMfLVhchuRMdG0/luAIgRLJ438iYWMNeNfrMpZ3AdkwIYDvAkUV9dUANWkQimcMdrnIU0ub28C9"
    encoded .= "35UqKcBWFDA7EigDJtOxRQzXqto62ZyDXVU4PeqsqgKiERkG6pFz4I5AzSYaglRDSurjP+2XBOc+rnD+FsrMkH/0MPCxv8u48v3EbfvJwTChGRLbluBBHFM7"
    encoded .= "pGBYlJZF+jbWgc9fRXzu48Q/vBU470cSz/sRkdG8ItrUghOfAJKIdgL88M+KfPOrwis+QDUMuwofL1eshxIEbq/wEiEEyfbHHrtZmBomDROQZKa9dwwvIBhh"
    encoded .= "hYsJ8WpXywSCFvOXnsR1ihZ7Fs7FucgrUy9GrBF4bnRJTdlmqng+cpB49BMFj3uaKPA3RfMEts96MBR8/uPE37+R/MYNxPKSYHmHeFk62d9g4jaLFbQSKtUS"
    encoded .= "Mbeo9xy8DXjnazL+9QPCpzxb5H4PE7QTOr06BKX00wFPf37Cddd2uPWbwHBOvIDWk5BUgjHbyU/TMzUqVsLKYlQW+zhKZbOYo2QoLfUj8PX6TOy3BUmiMiob"
    encoded .= "d2efq+v6XrmaBYUMqfFzBHCwF6qC15s8FOo2Qh0rCbBxlDjjPoKnPlNrCHpFFSbysupiSYK/++8Zb3pJ5sFbgO07E6QpdYVWbGJEXmHdM3Z1XYUQSnHqYAgs"
    encoded .= "7QS+cQPxF79J/sPbiMEwhUXVJkkjjgtLwDN+VTxSGI1CSAj4FJEft7az0HPnjiGRSan7DQjfwIIKS4cIM3LHqZlp23Jn0PQRK4ZMnUjYoy+lyMN1c92ISU49"
    encoded .= "myVwWFUPvbN1glow+DhgRLnpR58FWVjSzy7Yyo3MZo0L3vJ7GR+6lFxYFIxG5sLCK5ftZJqUxLPIKspLPCOEoSkIVryOPbcINCPiXa8h3/VnZDPoVwLb8lMC"
    encoded .= "JuMs3/N9gkc9QSVYGki9Kdwfa/2iXdCz/nOEi9F+Ln2UsHssvD1Gm0kAE6ByvSOriJhSjOD90rjWJh1KvkMfbkSyLy2cgyVkyazvoPglAUduJx5+YcIDzsFs"
    encoded .= "0Z/1vtwCb3lpxqf/kdyxu7iquep5W1OUGoBgfRVYPQCsr6opLZg+kk4/a2BJ3AZa3gV84O0Zf/OnxGAwI3ch1TV74s8k7NgpaMdxncWwy3U2AbzlvmLeG9JD"
    encoded .= "GXC1FaYGZlVzcjwqIOeikclAYcoCMR1ti7LcOKAI0Cpadedi+bgvxhCf+kkik8MEarm2SbkJsLgN+MFnuIPQAxJKbUHTCN75p5nXfJzcfgK84KIikarFCp4y"
    encoded .= "IRvrlPEacPf7CR7+g4IHP1IBvLaKcloYpkLfOmqsLdh+AvDBS8kPX6pGZ+76yBQRTMaQXadAHvNkyPpqMRzDGokpAnDmMKBVoDu+e3oUqDGV+lwhkJmm45ZG"
    encoded .= "oBCqZ4J13hWKqlQgTn2scyuAxpT7WDr1lc7gFFtLedYDJQ2wdhh43FMTTj6DmEzMXauPZBLDoeCj7yL/5QPEjhNEEzJBuZtUAylNEqIRthPIcE7w4xdDHvKY"
    encoded .= "KnJu+orgXX9GfuXzwGiByBQ/ASuLalv6YT6CriWWdgDveV3m3e+f5D4PFUwmIdlk4egseOxTEj7y7oy1DarrWlR4DD85nFxqcoryIwDoSbJgU2KTLprRZtsA"
    encoded .= "bLOdX1o4ksalCeKJIi/5lsodXdk4AlRuqaGCQpZB3Pc2hGbjUPqiKWp4zS0Aj3piWHVQD8yC4VDw9S+B7/+rjG3blSs7ApMc9hQWVYJit+SOMlkjfuzZCQ95"
    encoded .= "TMJkQkzGmjE87d4JP7s3YeduYjIuKVVYzsITt1AbRqfSNCpa3vEqcrwO5/A457YDdp0ieOj3Q9aPoBKIwdEYKuh3q5PQk0NzUWFE12U/Os+ZLSTfaKL0eAmg"
    encoded .= "SYOi7ktdfoZoKLKczGkuYjA0zEKOet8LMos9ECciJho2fVV0XQFuEmBjDTjzYYK73UePmu2ncFVO5gy8740ZXSsYNOIS0/p33V8AlAmZrAtOu6fgwY/OaNus"
    encoded .= "RmCjruZ4g9i2XfDQ8xPWVwNAC9XN2u+fO2J+kfjqF4l/+luiacQjpL60ArDvfTyQGlZ31xiMooJFqc1lQhX54l5JtbP6KsptgqAiMqN8vgMC6HLhrymr2ak+"
    encoded .= "4NR0fIwB9Eq0fNj++Cz6zJ1K1rtCcNGR+7DH6gCbDoDMwGAAXvMx8t8+o3bCpKNZ+BV4FV7FewEmLbH9pMK5jCrM9DvlxNMN+OZiVWR48WtYWs7A/CLwkb8B"
    encoded .= "j9wONMEoJArxZuC+D0k45QzBxlrFlADIJVWUC2Zpy+gRX9HCpdijHz8qX3qWVu9PXTNTDhzTDdSFhkAPijUZdJUBNAIYdi0MGZEgRW+qANBTuGKewLNzorV5"
    encoded .= "y9uB+59dHg8iExRIOYj6n95NIPUYo7dfbhb9G+dgs/FdZywuMXolbL5uC5EWM5tZMBgJ9t9IfOJDYEo+hns7kxaYWxCe+VDBxjrcSJWSgGVgsr4Npb8sMBbD"
    encoded .= "xBXd9Xqst2y3iAVvQQBDH61DRWbxL8X848oJlWAUFjVLaO6jlEB+9AZiNK5vB+gNIsDGBnDqvQS7Tlbx702036YBrr8auP5aYGHBwqyhUDTMPeLV5Vkq98fl"
    encoded .= "GxUhEqSaYYFo/Nb+bimVUoMR8Ml/0JhI3xbw1cuZZ1f95P59YK/iiSpMC9Y9Y+rSrJ6lEHWpV20VdbVVm+0GcqJSx2r5slrZbUuxQEVEWnVVNM2qrmDdRmV/"
    encoded .= "63FouoAmqa51zSHwhIwvWtSnv/dZOkIsNbP5AcDnrlDPwA01M1BLv9F+rjt87HPQXdbCNUmCNDBCMYFsP5XoY3k2QQznBTd+Cdj/Vc1TRBzY+He7D2Rh0Wyn"
    encoded .= "oCcy6AdnVKQUJyqmfoMUo/kJAqs99BuOYQVuXRZuhZte3lN1sITCQLPum6TBma5wqYvxwFt2fq8VcfSsVQAygKZri95nVkK5230iGm09gtSohX7dZ4nRXI8B"
    encoded .= "vF+BFoW0ExXPdghFSsB4nWjH/TnWAZQHugkwXgMm8+Lzb0SYEpBG6s7Yfgm3X6lp6SOHiS9/FjjlXmXDRq9rYNfJwPbdgoO3EYMGXtbVW4TYQoyITc8yfG8S"
    encoded .= "oWRjUbOtFmVt0mA6tgtgy2wgKLkiUc8rN47TFThhlcUcOQQs70jYdVKJ0NmkWEqnbJsWCld56LzQbQMcXSVu/BKwdlQwt6gu02hecMJpZa1m7Ki1hMEAuOVG"
    encoded .= "8NabgWYk6AqQbZoCVQlrtwM7dgnmtsGjmE0jmFskFlZiUXkP6gBEFraBp99TsLITvn9DSDmySnzrZpV2zdBwIn4wBRtd+1evBR/95D7uBUDbEttWBDtPAG7d"
    encoded .= "Dwzn1S3NBISkmjPl/3DaRNxK5/Awne8mdd0+RwBCCXmEO0EAAFQ5ZPQqVyEzwknUmrjzniC48BnAzhOTwVOCuxZIZbpFG1dw01cy3v7HGV/+vFbXDueJ5R2y"
    encoded .= "6QlzS2++nlg7AmzbjnAYJJFEmDsBM+TCpwOPeAKwbbsgZ4hGIDVh2jTiSaW4qJSUeB7yGMpDHiO2Lb9wFzDZIL74CeAdryYOHRAMhzEbp7BLQ1UB1l8PCiV0"
    encoded .= "v+MEgB3cpZbAZ8bz/a12IQwvhvQYCqarOWfSBujajTt/SFSiaxH27ZsQQy0dHz0CnHM+8PRfTdh9CiQzC0umqmv9R/R9Alqy1bbU3/VH2hbSTrKcdm+Ri182"
    encoded .= "wGlnaN8LS4L5bZFWIhlQDnzT1AlDnF/QEXJ0lfKUXxT88M+J7D4VMpqnLC4JFhaJ+W3AwjY11maqyCJ6JQlSA4FQxH4SZbQAeehjRZ778oTFRc34JYHv7COB"
    encoded .= "JgkOfwtYPyJqB1T6gm2q2bZisYKiUo3KDNGmio2jWYnFkDNTw8eczDHa1m4gS/x4OgZuxh/UQFtcEvzvP5kAZJmMpeoom1UYX4TuxlnOwLZtCRTY4w3BaIF4"
    encoded .= "1JOAPBHMzWnAJG/SYAqpI4fQC0i597AG3OMBwCN/WKuDJ2NVaW0hxNza+4uCLp1uhQg8HWxwKGscrwMn3V3w8AsFa0f6ASqSQCI2NoDJeApHQeiN5lG8JACi"
    encoded .= "J3wVywWZkK6kWsWijyGcboduKGzjiYJwWwuCGbCr7RgEUBYfOD66QJK0APLE0wQ7TxLpOmhBg82gGsph0Zs+lsnDLaSUdJmn3zuhGZV6liSbn9PVcWPdjDAz"
    encoded .= "7fWryRi4xwOL4cqM1MCDJvHnDlsw+s3QM/lsnsE9zgKkhIEJjaCiuKK51VrE2Y01NG1GHGCOQFH22lfPzTPdb/8y7NMo9/aynvp75iRmEkBbVj69EcEHtYkk"
    encoded .= "wca6YLKhMeCIhP4D4Xf4XupVf8Io+sB+Yn29In9TKxBJye6pXAopOtsDMFvQebTK7qhtkrNmKKqHAQIdKZk15mqFKWkqCBf+Eo8pEPpeK5M4EFUnAdn96mnj"
    encoded .= "yKlKsiCpqrrIkC02hhyzTsyWYqIkld0C5hEMR8BN13e47mpB0zRoSw2919J3/dNF9Lr4920Hifd3nZgE4JUfBkYjwcY6veZu1gq2rZTyrqCqcksMRsAXriK6"
    encoded .= "Vv34YhD2f1ykb908DmL3l4My1XBUUX3lB90oLc8oL+csmF8QjObhtQNApDfhxnpFXDzajqTaU5lejCImtpxYxOfYDwdPEQGBLLNXOtMLmBC5YfYIkqkD9UaC"
    encoded .= "G0LNfb/nDeAJp1NOOt2S77FNp8T6INjchO/578TV/wJsW9bNFeO1xG3LiPlOv3llF5w1oms6GgE33wC876/IJ/5cQhrlKXFWEda1/X7rN4LBYJY1Y3cQl/2N"
    encoded .= "znVxmyFZ3FvqWmJ5p2BuAdK25stJwBhx5Haaa8mexxVhFs4P8KyfKyPts6LXFIPOI5kkH8x2+GZelRaJybJOFuMuiYqwRTwDGM0Jvn498YpfJi94MnDG/UwP"
    encoded .= "6URqQYi5KgqAaQoFdV/fpy4nvvhZNS6ZifEEWD0o2HnSlCVTAHLy3YWDuVpDB6tQy1qy9YG3E9/8aofzniRc2V3HFhF0HWVuHth96lTXZY6SgIO3Qm66jkwN"
    encoded .= "KEkkl7z40cPCT3wIuOoyYH4BSKKZUjMUkqjHc+I9C+KyndyhkzSD8cAtVnQioL5sAGY/aNqaPmfDr5EQDdHephQ9De5E2sLimR0IIqThNMFXQ6QYx0rlmZib"
    encoded .= "Aybrgve+CaC+FQH1NTJaGeR+qqlOA3bR8TlnoAOaoWBhSScuDTBZE9x6E3HGmSGaVvGPU+4J7DxBcPCAh1x9e59AkfPpfwI+9zGiGXQeJEoDwZGD5AMfLnj2"
    encoded .= "y0R6xRtQlTIcAJ/5KPGXv0tsPwHImbTA1mSckRrB4jIgJXRbwkDK22Ui935QBWSw39A0wOEDwK3fpAaSCkw0GUwv+9W11tI87cjrg70/BuTH69ba49kXkERD"
    encoded .= "wf6WTkGv88KwMJdLS7GAbcv0EK6XAUwFoHzXTzC+TDKIhDi+6HtyugnxtS9Bzr5gSvaDmEwEC0uQ+zxY+LH/m5hbAdsubJ0UBejikr5d1EK24q/thMwtmlkf"
    encoded .= "sVc7kATOLxLzi1r1Yy/BGM2rhBCP/pQnCqFPWmBlJ3C/s8v1FGBY+t//dWL1gHA0V+oLICAo8TQQP+olxyggxWAQluruuV9ws1yQtrABZgeCkjE7e0GHXqbO"
    encoded .= "BylTgkbO7I0emboz1n4yidyBVsHSdaVqp6tI72wTphOGlkxdf21xgaW/QAPAQx8r9btSxCYFGdSNPcU5MMVZhGeJdpq5W/twkPr2NDvGzjUsQeSguM1gLlfG"
    encoded .= "R4D7nyvYfYp4osqhVQb58tXA0bVcI6Ym9lEZrZ6kMs31dT5kTVfXsrcpAjmufQEVRgCkbskqlp+Xd5n+LhPSSzUnjfAdKcji9Iwa6w7zskfKWMzAaA644YvE"
    encoded .= "t24mBkMgLkNEiea+Z0POuC+wtlYYph+8ohQPJkF/dKqCJMK2jSCtxt8mWJQBhURTaU2tdZUe4tRAYCCCxzy1kFSfLa3YBNdcmZEGcG4P8rVs5JgqJyq2lZXr"
    encoded .= "9dVCHKHCz/B4XBtDJm1rnF8De0Q4zgy17jxMoh6LRkwPR7vRU8LidoX/2AJYqboZqq78t08X4ToFk9wpYZz/NMFkXXvwYIgaQBILQzqBMOlUsxtmTtt1vma0"
    encoded .= "2OL7JpFWbcW4b5l7akTWDgkedB5w5rmlhK2pT5KCwRC49WbwC58m5hekBI68Yy0JmmIMX7LrzkIQwJT21/nU7IH+nnTdzNOQZhKAyCCBCVa/5mouUJsbYw4w"
    encoded .= "+Ilg0lgywtiwOpCVxosecxU8Y7Vm/Sbgyg9oP9PxAEvaPOx8kQc8TEPDVpYuFUiSMyRbXQoAZKIZUg59S+sMKvmZu6W37b+RVX4XKhUXg9U4EmhcoJsA8/PE"
    encoded .= "k59VZN0UI5S4Pz9xecahA7rLKNN0eh0jE15ta9bBNMxryM9DAn7JtpPby7c45SA4/GZdBJxBy+cqyeKbPCQQBGj2QpHsU+5JFckm+ekTr0TA/nO0HTjEtZ8i"
    encoded .= "brhWa+ymz7yz3UBPfU7C/AIwaVEOrtiCtIp0mZsXfPWL5CcvI4bDRoHXaRXP3HzCwVuIK95HLC6ppW+Iz/VYDBUFhGb/hDhyG/HEX0g47T4QPTmkP4FmALYT"
    encoded .= "4CPvLTUMPRG+FXdvXouJ+N66IL07vWsC0s0+IGJ2Uai0hGSkpNEmFoSZv26Rrv6kJJSCmVWLTf5IXQ76mz96Eo89yIgA6+vE5e8umkT6HUrS2sFT7wX50WcK"
    encoded .= "1g6VbeE27wDbIuqpxKxbyt/2J+QnLtM6huFIOByBX/sS+Ze/TRw6CAxGguLl9U56MEMT1LTy4VuBh/+gyA/8JKSdcKoUTNCVAperLsu4/lpiOK+Z0VTw7No9"
    encoded .= "aFCBIOX6Ak1n+jqNPvBEnIR6RZFbtNlHxXIgtvGToX+Hewp+adQOgk0iL6pPCUiwfv03LbRaxaZFznIHLGwjPvbBjAue2vDuZ0J6W8OomcR2DDzqiQn7byTe"
    encoded .= "9xZi+25B1/U3oBj+uqy4awaaOHrD75F3fztw4t2I1YPAv31GsLGmKeO4Paweg1gDW80AOHwb8D3nivzU79Sdv9Nqs2k0g/juN+Zi0Or5RdGOAIBOsp8P4ucM"
    encoded .= "GhwDjO10tLqT24y2IrGlkKkIMDiuolB4Jw44Ed8D36uhCSrBd7TGJFIknvIPi8jsncyNahBa0+7oXL6xRrzzL0sZbwRuMTwlafj1Kc9MuOCpgtu/VeYbDVYA"
    encoded .= "ncHFEDNQvf3VLxJXvA/43Mf1i8UldWkF0DIwi/HmKn5TAxy6lXjAw4Bf/G+C4WI5Jq+3aVXX1TQJ7397xnXXEvOLQMrlEDRCOpY4RIGBSy6AGbl3LJTDm9MF"
    encoded .= "oX2cIfSTj7cs3HvKU5eK7nF9Hh0nJwQ6xZpv7erfJopwHXDRFcVfvUkLLhaXgc/8M/GR/1n23+Vp/aJVcW1L+YlfTfjBnwCOHNCkTNOAdrKJbw7pAUpDx8s7"
    encoded .= "gJUVcDAAEskGus2FJctnL0xukgBZcOhW4hE/IHjWK0W2rehZgtM7gvSQCuD6azLe8Zcdtu1Q7yCDcJ8Olcmbomskg+wAycLN1b8MesAelt5XEYbHHQcwgJr/"
    encoded .= "GIMNQQP2dKs/FtYfVYVdiQVO8DXQd8mkeN36Fs2zzy8Bl/555o1f1gLSbAah1GcEGmR66sUiP/0bCU0DrN6uETZ7/QtYxbmYe0tots9FnHZqMQRQbYskwNFD"
    encoded .= "RDcmfvzihF94qchooexZnOJ8+5gzsLQDuPeZwNohtT1aUGwjCKZsqqIMRURFQ8riphGlYM6YxiAbrfJih1lrjtcLMOhPk00luPqNfxIEw6RvqLgBkwP6o663"
    encoded .= "hYG9YgZbbCrFF2lAbIyJv9ybuXo7MBxJL9Vq8wAo7QR45BNFfu1Vggc9Qqt0jxw2cVyKVR1exQaxiiUKmSBIIknLwgAK1g4D64eBB32f4AWvSXjCz6rBl/P0"
    encoded .= "lrUwnbI55ITTEl/4qiEe9L2CwweI4SBsW4Z6GizelNUCxFhDzw0046kAq5e62STdeHwbQ7queGlZ0Hvb5ZRoqSK9XlMf1DaOBCrse4V9Q9DyA7bAcPiFcWq0"
    encoded .= "M+YWgBuvI/78t3UT5nBYy556xJgEkzFwyj0gv/TSBhe/NOFB36dS7PDtwNoRKeXiOnYSreNDUgksBPIEWFuFHL5NpOsgD36kyLP+W5Ln/InIPc6iTMbcVF00"
    encoded .= "pYZtUZhMKIvLkOf/USPnnCe4/Tbd2AIQydm3vPjR+FkETJCcIHSOrwB0GEd9KlbMY9u4eHyHRAEWm6eLAfqPYHofM30ydg+LdihnChWxyXh/CCn76Tc00ZfF"
    encoded .= "0tBJQH2vD/2a2QOfuzLjNb+T+KyXiIzmZh0aoX+3EwGEctYjhGc9QnDTdcDVHyO+8K/EzV8HVg9qlS8JfcW7qHE3Nwes7AJOuztwv7MFD3gE5PT7aM/txMrV"
    encoded .= "toKgobOuW/cnCOYWgF9+xUBe/aKWH/tgxo4TEvKEyu2CaiP5UW+FQRjEvHecql9rHOW1A6aqt8b01ung6YtOXVPLCkrL6MJFlPstwRZAMVaCe2O+rynlOFQV"
    encoded .= "70FUQnX/yg7gEx/N+NMXJj7790QWlwWTsOfepilJ+28nagecdi/gtHsBFz4jYfV24sB+4PBBwfoRoBsDwznh/DZF/o4TgcXlGqttJ7oOVx8BPqby4vqJ/n2p"
    encoded .= "xCwGQ+C5fzCQ0e+0/Mj7MlZ2QdgB8UVQKQuZ1HxLUs5a7EB3R2zPfj+FqZ+i8R65b6ptmQ62fnNAcM/yDyK6b/DQS8kiEjzLF76rYr7W5Vta1B4usUIkd7tL"
    encoded .= "2JR6AMTSduCzV2a87HnCZ/+XJCefoVu7U7PZLiiJekeiJH1+abvd2aNw/7udiEu1aDdEV1f70yKWeCDbtOVFFHe101rGi39/KGkwxofek7l9t6acTRKKVN1u"
    encoded .= "ol5yBL3UwU0KFwO2spJY9nUmCWwtwMw+KYi3oFAlgjIpqWLfqCaC06EwrSPtGRoFm7apN/r+OGq8vIRe7XEQLDtsgBu+QLz04o6f/metUkpJg0DTjcXqN6PS"
    encoded .= "9irYwRD6m3pYxKSUiyUiNRLEfZhjp5gaDHW30WCoSLDw+ZbgLYZhR+JZLxnhCXsSDt6aS/pZbagO9BCgMXvd9IlaJzgVfVMAsX4GsJUOmF0V3CHZIR2bzsYp"
    encoded .= "Iruk0SvxBUKsVj9LWVlVFyzJCeNI4/wMOhHFt47oYzUpB6JYSJr11mQQsbAErB4CXvmCjm9/NTHZ0JPBACk7hpTAvNcwviQ7GCL89PYs2OTLfAh/3/BwpMUw"
    encoded .= "H/lb4Hd/qsM3rhcMBkDbcTP7TwO/qKauA37+d4byxGc0uP1WusSOyDfYaupZpmDWE8H+oR7cKWia2bOZrQJqIrCu2DqVCkanLsM6AhGU2bJ3X59SlXgtt4CY"
    encoded .= "6iWR3eqtNYa+Sc7XSkBfQdNp3WMzAP72f2R+9griqb+Q5NwLgAZ6uFU3LqBKQW1ugaTeV0bkZQfPcGTfCj/7ceK9b8r43JXKni//1Yxf/+Mkp9yjHCM/bUyF"
    encoded .= "jotKUyO9BX7uRUMZDMH/+YYWKyeksC19ep7sMxxCwW7R2S6ASmn6VsJoay+A5s7Vh110w3BJ5xDLHZQ1lUnrN66PDOo2efYXYzIuk+GNa/a8ijrjAoHeJABz"
    encoded .= "OGBHErCyU/D16yh//Bsdv+cc4PFPTXjo9wvmF6uz1tsVNLOJj5waYBAQuXpI+NkriMvek3H1VTr/xSXdwfSNG4mXPpf87b9o5MTTZngmMwjOdmK3E8FPvXCE"
    encoded .= "1ADvfF2L5V0JvbeTTk/XAiVRvaaKo4IeAlsfEbPl7uBEgB3FREic/zQhOJ/27g2cGkSFpX8N6VZtJKJZMT9djegRX0qkCNHSUkZicKuDFAXZtcTcPDgHwRc+"
    encoded .= "Rfn8VRmn3kvwsPOED34E5Z4PSFjeYas5VjMNSdx6s5amfeYK4jMfJ751IygNsG2xiOOs+yC3LUP230z8/vM6/tarGjnh1P5xtjOFTtEWFGAyyfKTzx9yMATe"
    encoded .= "/uoJlncnV53GECJSYiO1elj7qbujzVb3reJbVIXOJIBBC3gVvRiS6wIC1FVYh0I+zW5VA8htvCAdlG3LfWI9Vbk4XYWqJ1YJsiRdpBRXgC7ugpHREzSY36Zd"
    encoded .= "3fJ14L3/Z8b73wbuPjnj1LsDp99bt55v3wUsLAuaoT403hAcPUQcuIX45teIb1wHfONG4NBtavTNz4PbVlAQ38Mjcqv7GW66LuMPnkf+9msGsuMEKeogsFLV"
    encoded .= "qv5bijc0mUB+4rkjDIbgX/3xBCs7rYCOvh2tsKjVoLq4BwAph2SVoLsWxMrsZNDs9wWIESyrVe86xwW6i/5NwsUTFaaLKgXU4mn0DAQG3CH1VQRExT5QDCRC"
    encoded .= "KPpKaTsrKJPFgC6SQHvV/boQzs1R5ssOndtv03cBfuYKfd8xEiAN3PhkRskJ6IRGw8ThiFhaqkjvId7j7kWKtZClFeBrX8546XM7vujPGtm+u9oEm6SA9H8n"
    encoded .= "qGfytF8aiQjwV3804dJ2KYyjgMtWrV1A3dvjapVZAcgi7Z0ngJTU+u/h1HDlNf6BiD0vjf4X1sLRsmLyDlWk9awcqSqDBZ/VrzXcRhljdwJZWMLulKQBA887"
    encoded .= "CmAV7hgOgeHIVE2NQrrGFGESFltDCda2tsWlqTSseVyTSom6SWR5RfiVazt56fPI33r1QJZ3BHWwiWnCtQKAyRj4sWeO0AyAN75sjJVdDdQDM0lSM3USwFhP"
    encoded .= "nq/rIme/NWzrkjAASMngHS5GkBtXR6YzOBYXxFLHlrTwB1Bj2D2Awo+hl9hvFUGF8/WjBQo1ZVsLQp1IWV5ubUfeFdeUHYkMMoN+sEQpx0TWF0YgC9mBWhLO"
    encoded .= "MPEc5kNHGEHkBMlJDZW2oyxvB758TcYfPK/l6iFNXm06iHsKtoBKHt2AQjzl50f4hd+aw5Hbc31Bt1SAmxkwvUU8bh1PnL1FeTYB5MKzDJFAK+BwfNRqVgkU"
    encoded .= "Ql9NeDOo1AUWScnexfC0iNkA4gsyu0ARv0nxo7PdQARyLnssaa+zL+uA7rV3+dMT25aRnSUl44oC0Qc/mdBqY8/c2XpEbYLlFeLzn2zxsue1PLpaCkFnEMHm"
    encoded .= "0akvnRhTnvQzQ3n6cwY4entGso0bbjZVxHv2NTAXBUhb2ACzA0EJyaN7DIiMDBvtNIOFIa/8vcngKdcz9U0wLp7QL29m/AlIYVF25XnfpxhP7dR8vdBL2sr3"
    encoded .= "Aq1zFtSbvUCEJcJIlJ3GrNW24V5Ax7fi15zVAG5JoW8fDuoSSjTtBFjZIfjclS1e/istN9YEw2azJNjEosbVSSOTey4eycMe1eDooQyrE9jsUdSD5ip+ZMt3"
    encoded .= "Bs3eGWSnhYsgaRk9rRrbAT01Yz9SzsSsfW/00CMeLwudwvZmJrSAQOf8J5Uog4jb3AhaWpXiSRarR4iGG4ByIAP9EGqPYmpPOv+ObgibdMlGELl+F3dVG6d2"
    encoded .= "nR5U9akrOrz8+S3HE0GaQQSbl1F0XgaAho98wgDrR40YhegkatjiMcFs9TKHjHxcKgDonT/g7GzuFX1entJl4Z6e6PF/KvJ95y2UaDIrwMoNPXXB+lTV+Sbi"
    encoded .= "DTGoY5iO15ip6pQslOxnrNR+KWUvJggqLKUTCpPe35XnNDefkYsBlrMaiFl0C6VkkJY8KdjovVOhyLZuDK7sAq68bII/fP6YuRPeIREU4tY8RMZp90qYX0x1"
    encoded .= "x3UmpCBcOtDef2P4M1w2efYoW28NK5AqhpNMA9oA6Vj2qEyQ/QHgFfB9ItEZ1ttdpFv2o/wkq5xC6QP1cxUkLKYKS6m+Vpb0cwllTYo31JIsMdxNC6XC8UZg"
    encoded .= "OuEkKi5yEZG6vhCiLesAC4JAIAHdhNi+S3DFB1v80QvGYJZSMdQ74WcKExaVVEPXWrZNgLmc5h0Rk0GrLEqC46sHCGP7aJ6WdySXsad0HljypSYGQV8YfSGh"
    encoded .= "D/dVNy+7diyOVOtnisbCgyzH6tDDDWbACQQ59fUFqQacDSjltO6cIGYDmNlpVTtZoAUqpXcV87aySkxSbAudu/o0AiC3ej7gR983QTMAf+XlI4HkfjXxFDSM"
    encoded .= "f6/7fMb6GrGwTRdZAVFWqVMqRnH1nyXfibeGnXWWriG3PFrMBjEEOBdHfAkigGyqetS56x/xAIvvyxKpCEblFpk+6wf1Jvu373fQvLBYU1XvJ8tYOpmcalCy"
    encoded .= "xh/s5ux/RGkhtNCDIJcxXOkWDjA15ZQS/qRhqVeypmno7bsSPvSeCYZzwHN/f4S2zf5W00jauvNJgCz4h3e1mJsDpDPBNVOU1m9I0dLidASoOLa2RSg43z4W"
    encoded .= "jCEyRCnlcJ+8RxDKYqkEH6xoIhcdVFkt+qz9TSWMQCsIqxKEPfRPy4pIJB4aEnrxiNkLhhGHlfntYQ1GkRkQrUlUl1QrcghhiI2RVTi6P1Y4nxp3MHfWCdHn"
    encoded .= "UR/rOmDHCQnvf0fLlCAXv0QPLZxsGMT1scFAbYA3//EE112bsbJdaiKr9BuDQ7bapFohdegmgsEhAMAlU7iOf1xyic63WZ6/FUcmB0Wak3Juewagk5cPPrvg"
    encoded .= "3MFSYdNLAkXk6/3BEIgipvwrBGkpALuRPobXkRHlWFSbG+HVFCw3mhpVy1DQubgvcxSKVHeqojIz7IpSoUOUxASrXKrrKPAymi79JAhZVBonwu07If/XpS3b"
    encoded .= "FvIzLxxix+6+LXD0MPD214z5ztdPsLw91bOJIx6gBmo5ZQ8OHGkSkQ9O2vFtAHDJlNacYXVQgMTn/dDGvw6a4bmTbtzSjEXCjSFDgC07cnLf6AuDuRfBYEDq"
    encoded .= "U9k0e4/7qy6Fuv2qQw0zIpAOzKaPqTPtjZlZNC91aZmaMi1zTRns9CSlKdBUg64CW42qbFquTISp4t4I36gi4iPTtnqWTR8FPlkgkoDDB4mTTiMe9QMD3P3M"
    encoded .= "BiLEjV/O+PiHMm66PmNpRdwIVLNf55zK9uJ6UlnZRZ2Qm2Zh2LXrn3rrVYvnFHY6tgrYez6aSy5nC8GnU+K5yJJBph5jFu7yADRRWT2QVNXXAZimIKuMcEFf"
    encoded .= "iQqOfOMge5QF8TZObsppNj1VotOR4iLlBLFnGPQroS5i5FYdw0rTanyfEOV4QZxXT/JEaqlrEsd0LKShxnfU+AfAlljeLjh0G/CeN3VgbllkG+YWBEvbpSSC"
    encoded .= "6jx7FMuqcujSDmyQ0BKfFAjPP//Dg8sv78eEtvYCyH+EyH/G9D4uV30G8DqJqKP7+rn8DhxfNKZ3G9Yx1aoaMAL3LH0hhkSws1eMlUI6Y3o1/BSWCRYnKQQB"
    encoded .= "1Ny5BVzKZ5uHlmfpF51jMAjg6p3CBJjTsfVp5JsBuEEM788KaVm2kM3N66DqFZSzFlt91moNnXiCWp3en1CKqpDAj+iFCzZBd7NrcIHaq4NR98HxZHIUSAPD"
    encoded .= "oetOwCcyMz6AKUAyolIvxGIPxOfqHf3vevZCCB5RAzhVEhXSItAVV1AHpwed3EeHieTybA7rKVD1six7hsYHCvnoavZ255tw9HnaumEBiCqH9GQwXTMJtqSe"
    encoded .= "qxTqGcNEo7EHAGwgbIyYiorRFQzH+ega5tKHAeCCy7EpGLSJAC65RPLevUyvfPfi1yD48KgZAKJvo3dx56uUKV0OT5Q51J0CpOwDsCn2EY6wqN61MFbKViYr"
    encoded .= "MNHqBiUKCCMLTmmWXPbiRS8g5gvqWvSi7cdz4U0jzH70MgZ9ekRkWAuEaYSmcRsLSlHrH0WU44s0awAmwnVUk8HkkauqbvqS2QkzD5qFBOAjb71i8Ya9e5ku"
    encoded .= "sffLhjY7EniZXm8kv1EUc5vPGnAuqoBmvM4SZZP6gOf5CYikqBHR68iBp9cM6J2EkxIiAPxu3VbVlW1UdkpIBryg09zMzfGLyuGqMSoiTFqZ2ohwB1BzAVNF"
    encoded .= "IkYJDqYCxC7Z3oZALLlKRU+Osf4AZgvRCTee1kKi2De2Tu04d3g9AFx22RbHAc26WNgUz30CRsDksyLNfdvcdiCSGUQMExCaQRo40kSliS5DXHAbPVSKxKKu"
    encoded .= "KglMu4j2d5xxRCAR+o2/rawjILgIy2jgFQw5knOW6rYWYrM+BFKve7SNvt5pqVjnGFjVwFJcS/Sn5lJDsjAnEx01mGZqwW2jMnbJC+SmGQ3abvzlk44sPehV"
    encoded .= "X8K43LFpVlvtZ+Xe89G86n2yAfAPBsn2CvUx4NHriGSbe2/lFUEuKcusldO0G4/FhQ0hdTBXggbNnto3oRAoyE1NEOE4dfg/Pf+DCtRcdK/PwydP35yR41lI"
    encoded .= "QQcJ6xz6/UairICg72jViGOy3cF2f++EZ6nEWghaiigQUw2dht+YwJRGkkRe9qovycaePWUD4SxMz7pYZiV790K+8V40w92Tjw+awdmTbjIh0fQszwLQDNYM"
    encoded .= "mC+4x9OoYFfU9M5RYPAJpkSzODpjUWUle2cYD7cG6cEqauNx0T6afR8HDHOFSzeYMFHVEtUFgvXNMH4wlGHSAqiU4gyjngyIuhtCwi0CSOT4osLCFmJbFJgk"
    encoded .= "N838MHdrn9ielh556lXoLqmkuakdY2+r8JprIK+9SiZNwvOArAqdbs4ELiz6r1ThVYBstvS9995fVc/7QtQTMpiC9SyZ0MO08U/Uc+D6NgR7yLdBUAtUA/t6"
    encoded .= "rZjZDIYvCVC0aybJiN4+A7rUCXImGg+MvgPUNE2wsie/X0JnUtwYszkkx5tC37kjJV382qtkcs2eGVwY2jE3N+/bJ92ePWz+9H2jf5zk7r/OjYZDQtp4ZoC9"
    encoded .= "/NGbBAD7taJXCw9HYe6fA3D9pUeoadgSE6nI9gVXYy4k9YpRZZKjPyYD4qr5HLitXNcMf5A0/spOf8SUYL+v3lUbuxifYdubT6EnEEp5lx1ATbCh5iitgkk6"
    encoded .= "MGXfXw+i1DAA7TBtG3bd+CWXfmLbx/bsYbNvn0wdqtdvx1AB1ih79iDt2yfdxT+48XeDNPrhtfF4A4KhiX/Nn6JviMGAXC3AusAq1p1Di2GldYFS3pRdCx63"
    encoded .= "nl7P0yyX1IUjSyAompelZNqMuJ59av+WcjB7Mwf9W7PwTAVUEiDqWgmgyZ46dtK2aiagR0c9Qw4AUqersq1xRkDuJRAeDdUq6wQmtqO0NLcxWf37fZ9ZepLi"
    encoded .= "rJTFHKPdCQIAzLv+ladg++To5PIkw4dsTDbGKcnAdVU0XhCJQf/N6IsbAZDLolzKlocE5mHIZi+izsmR7q9zpzOFxtrNqhxYVqi+5NHGszA+QQil5hmK7rcA"
    encoded .= "Hln6FIh6MrSjXHzOHvEDIG2miNUfmIsXJENUB6V/FzYkow2lQ4rPPwxTMpbsRs3KqOvWPtk2C4/bdxUOWU93hNs7ON/C5ip88V7In7xbDq5z8kOZ7WfnR3Mj"
    encoded .= "EhNHuN0bSCpBN24K4lt7FHheChaIpkJGIa9HCtcOTUq4f10GNinhP0A9W0fq/ZhCPmiBoNhfJVvJoJWYpa6YIVNlb4Y5s+8SyUQ3+5wxgoKC67sQZY/LZ6rC"
    encoded .= "3T2tIpGmOTYL2lGzMsrd+mfYdj+07yq5fW8xGzdjcnO7UwQAaIRwz55Lmzd8cNtNa83a49uu/ej8YDSHjJa0l1xFTdtnWjERCtPL+slySDGCaNBzXe0cXiMt"
    encoded .= "PkrvZs2WOYJ0d4iYMab3W9DGDFb2uc9IREqpNwWJqW/NVrOgUpypCSOqRsSqivoqsHwm3N11WRnFgzjqYa5oV3Q9k54TwYRuNFie67qNyyY48ANv+9zyN/fg"
    encoded .= "0mZWxG+rdqdUQGx79zJdconkPY/86sKJ20599aAZ/NzGpEVmNxbR1z/nUBBZf/f1peMNSqt2llBsjjSpnO/6EPDCCxtoyuQI3F8YwlR4uVw1tk3UHjLCMB1j"
    encoded .= "TgJDurla34zjldhBkqqWzLqwwJFAAzwalK5rUqOehWoRiI6wrdAiQoKdYDAayALa7uhr2V733H3XPGi8F7PDvcdqx00AABAHetaFG/+JXXrZIA1Om3RjZOZx"
    encoded .= "hiRYbYJxBqwcIvqRcGSZUdabFvNUFVLV+xWbNoqE7HQBtFup6I8JOEFVGwbel0iNUERpH3VVfb+rhFiCk0addxi3eisRLuipJmtJ+1SXT4tP0Qg6iAxHaUna"
    encoded .= "buPrHSe/ue/Ty2+exsnxtDutAmLTgSh79rB5zQfm3oxm/ew2t68QpEOjwfyokeGAZBY7C7Ev3AGqbZCcl6cRzwAVKzkv3/eQjyLyp3SpJ0R60QWXOLUVbmf/"
    encoded .= "b+uLJa4xi0vE/vXwJWGKIuYBamd2W1xrjaROB8FsmwUaaZkyGxk0w2Z5JBgcadujr+gwPnvfp5ffvGfPpQ1A+XaQX9fxHbToaz7r8Wv3zhz8YpdxUUqDezcA"
    encoded .= "JiS6vEFoOt229JbIFqe8B3OTirSQyqQA6r44oMbcgR5Wp70PX2S4HusSPdpnzweJIJsGMk1RXNUgkQyRfYoz100v2PS9MLn8ncHCiWJrSBAOGo4wkHlkaUFM"
    encoded .= "rhc274DwtX/9qfl/m4b9t9u+YwLQVmMFAPCfLvzGtvnJCT+AzCcB/H4i3zs186MmVIw7H9AZtnQV9iNOi097LrLxlOzsi+w4Rfjr96Ycg/o3ZwNkWmMVyd97"
    encoded .= "hgA84h7m6vM2Yu7bjL0+bT3MLbpubR1MX0pJrkho/rZtb//wvmtOXgUM8Xfs49+Z9l0iAG17wXTZ+Zelyy9/nJcd7T2fgxuxfs8u4z6JuDtFdrPtltgkDQEk"
    encoded .= "tX6IcrqJ9HMk1k8CkJEFBJlBIksq75wjUwYytDgIwuzKmDkDiVmypGJvZes7iySSWew3CyPqi8ESc84oWWX/DqJFBdC5JuqWIVByEkkEsso50VlTw5n6IrWU"
    encoded .= "hKWuK9bSStaosYgcFuGtSZobm9x86X6fnb8+ivY9e9ictQ/8dsX9rPZdJYDaVCIAGk7+9xnj/x9tzx42APDd4vjp9u9EALFR9gJyzR7I/v2QC47jyfeuXiVP"
    encoded .= "WjqXlwG4AMBlx7h3dRWytFS5anUVAlwFAFhaOve7Drit5qDj4Tsa76STQOV0d0Dvav8xWnEb7mrfTrsLcHe1u9pd7a72v7b9P+iHClvezLf+AAAAAElFTkSu"
    encoded .= "QmCCiVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAADiw0lEQVR4nOy9eaBtR1Un/Fu1zzn3vjl5CZkgkDAkkBAQZIY2DIIT4hgGlXZsZ8GxUds2"
    encoded .= "pPVDbZEWFVtQtEVbJZF2BJwQEERUQBASkAAJBEIIyUvy8qZ7ztm1vj/WWHVO4F0kiN1vJ/fdc/epXbVq1Vq/tWrVqtqEE9eJ67PmYmr/Jv63oeP/nav8WxNw"
    encoded .= "4jpxnbhOXCeuE9eJ68R14jpxnbhOXCeuE9eJ68R14jpxnbhOXCeuE9eJ68R14jpxnbhOXCeuE9eJ68R14jpxnbhOXCeuE9eJ619x0Scv8n/T1aeanrhOXOuu"
    encoded .= "/3dSkP9vUghiZlzxVJQrL5B+XXgV+MoLwM+9DEz/Dw3qievTcTFdeinowqtAV94o8nTVaeALLgBfdhn4/xaQ+HcNAJdeygV4XbnwwsfyU59K4ycr/8Lvee/G"
    encoded .= "5tau4eTzz+LDB8HAtQDOwYGD19H+vWczcC0OHjiHcW9g7wHQtbgW+w+cwwBw4OC1tH/vgg/sn/P+AxfScnJd2X34bDq0CzxZom5uoQLA9WeCHgvU10WzBdde"
    encoded .= "W/buHwg4GwcPgPfvhdS5H3whgMO6J+Paa6/FOTgH1ypde/eDgOuw/8DZfC2A/XvBQsc5DFwN4D44cBC0fy/4wA3gs04GH9tA2XsQJDUA8w2UQ7vAH/4wsBc3"
    encoded .= "DrjLaTh08AbePZwx7t8LXk6uKwcPSN/37j+HDh6+ni4886zllQBwLcre/aCDB65lHDmn7r8ddOD0kJmDR0B7j15Pe3ecxQdPBgHX4+AtI9/tbmfj+o/fUIAz"
    encoded .= "AAC7d4IP3gLeuxOuNPv3gq+9AQW4Dsszzq4AsP8gaO8R0IfvBuDDwPIM1P03gA/eDcPeA2AcQT1wxtW0/+CUDh4RfgLXYe/Rswm4HjhlXg/sPYf3HwRhA2Vd"
    encoded .= "mwcOgnCz8PvgDvA5Z6C+D8D+G8AfPRl8yy2oV1zxyWXpkkt4uOBGEB6L+u8ZEP6dAQDT5ZeIhb/sMlr23/7aDx0+CzO6dx0nF4D5XAadToyTGby3Vt4DlF1g"
    encoded .= "TJhZKiNiZhAIBBBzZbYbwhkCQFzHCpY/GMwVRIWZCjEXEDEDlSuPRASAC4NGBjMYRAQiUAFQKjNxRWWIUFYQFzAqUwFAqIxKxFRZCZAmIaRwBfuflcFUhVBm"
    encoded .= "MMDMBCZCAVORkkzymRlEFYQJMRGDGSOERoBA4FrBAAaldwkI+QAXgCpXrgwiBgorAwtRkX4AxCAmMDGYGVSEjqQXNIKZR1iXCMxc9M+xCL+1PfmaiCpXBjMm"
    encoded .= "zKgoGLmCZLBkmIQOaYUIlbVuMArAqJUZVKQoMzOBCBikeTAYlUHMqCCmERUjlXqMBjrMVA5jrB+nQtcDfB0PdDXz5JoDu3HdS15Ciyx7l17Mk6tOA19xBeq/"
    encoded .= "JzD4dwEAzEzPfe7rhssue1yj9L/2Y8fOR6VHAvwY8PAgcD230PTk6YTAgGjaCIwMcIWIO6teIOm4twMw2r/tBhsC5DIMUyH/O/0K/eU1z6VybPWk75qBsfKJ"
    encoded .= "Fm+H29+BW9Zm0hT7vgpvAGBUaCMmoK5pu7sqhJeAqqu1S0GjbzFlue980PLVeLKmfrLGKeioNfF/TV+9ev1g9edO5yFyXnZ8B4R2KvpD8QMGxgos6/IwAx8k"
    encoded .= "4K3g+noMs39834grs9dw6cU8Ec+A6idg5WfF9VkNAJdeyuXCC0Hm3l96KZe7Hjv22Ol08oRxUZ9IRBdtzKabALAcgXE5YqzjCMYowkaozGLmGZQVgU2SQBIa"
    encoded .= "ZAInqWEWEyFXSDpXCSX2whgXheJRPNsDgPwiVT4TWrPb1CAL2/NJ8LlpryeCQugpfU9BLysCCFAqSHQa6e4BgApGMe8jabSzESuPCyXWLgXfXfm61tzzEjck"
    encoded .= "ANcBMB4yQKBMdmaM4Lx/Qcwr9HndWhklqCR3rMiqMU9xMgwTDIM0Nx+XI4GuJOJX13Hx6ptPvupNL3nJQxaAThMuAH82A8FnJQBceimXC68CPVVR9bd+9NCZ"
    encoded .= "Y5k9lSt9PWHyoNlEFH6+mDOAJZgY4noTc6XcrRVrAHLz50Ilo+1Xo2ymNBza47qZLYhWna2567F6HGKNtY3GLCZBjFvuSPqcIdUd8KB+rxJLVpCoHV0FmVAE"
    encoded .= "84Hld9X+mf/dPKfQSCQWsiatC5JT7zoFN6vOhMbLCPBQqKH4jkqAD1fhHdcWRKmT3uyF5EEJXnLj4QQQqZ+k/UOqJzkk4cTI5EakDhgmw7RMVCYrxncx199d"
    encoded .= "YHz581++4/3AZzcQfFYBADPTFU9FMcX/9R/bumgY8a0j8PSN2ezU5RyYj1tjAY1MKAARVwXoNOiVk3SwDR65ZDCHhedGSsPSmgUxKxQ0ijCZlQ6FTxZb+uIC"
    encoded .= "bN6FCzdRGCoWa+yKxBApZHna6fT+dN4AiYJYheKyUqsI1m/7M4lh1S/cqnul+bQYdp4ORGFZGRgR/NIxhCvdygiHV9UAgDKZQDD4Nu/JZ1GVE88y/OnjZICR"
    encoded .= "LH0CjExPAIUGLtJ9SmywcXW/IHkyRhkFjlYAwzBMh+kAzMflISL8PlN94fN+Z+PtgAWtgc8mIPisAYDLL+fBXP1f/7Gti8D0/Vzx9M3pdPPofAGMdQ6ggKjY"
    encoded .= "0HPSzGxBmUzhgeLGqnWV3TNgKZsFxxSKgTDDHO7uqgVJQrkiQAjLbe6tkJNcUDgYESXl0Gcrh7j7dEC/NpDIFxG1ZdzKtTQDMr/2Fqn9ztoskFgBEaE0xBFG"
    encoded .= "TvV6x4OnjfKkthOeeT8bOtaUyZ5X/tsAg9yrSYrftCkP2G8D3La/cWVgJ7MEHTBRelC7UIlQC2g6m05oPh+3uPDvM81/8ad/b9ffA8Dll/Dw1M+SYOG/OQBc"
    encoded .= "eimX5z5XIvK/+iO3nz7Q7L8C5Zs3ppPNY1tblSuWzDSYf5ktnMsss7jJKuhh8wOyxYVkl6rsqjMbYHD8ThpoNXn9HO6pjzpXuBubLLQpf6c3rhjMQE3WLRlX"
    encoded .= "/+DKZEBh6KF9yUJs5o2N9k7BJEwPB5Ze2fMlXoz1z9zyRBdD/GBQ4067oidrydbZBJJeVQYh7ZDFA5IO+vM+xlZch5mi6egyG0CyA0r2wFyVMz29WpLygkIO"
    encoded .= "mnadplQfka601OlsOqNFXdZS+He26vjjP3fFjmsAkf1/a2/g3xQAstX/Xz+89Y2gctl0Njn72NZWlaUoDDyCKtuQEygpsI0Gs7r9MDdeUd5GKFnYuESJ3AV2"
    encoded .= "yaFWiNPAZiOXiRALGOUqgKrV0BjT8ky3MT6ASy7zWLJ1snm6AYC1CSSPwerXOED1/rqd8kY8XM3xK4CHEm2cyoTn4g8psrEBgCtmO9d2eq08pzF0pqaOUDyH"
    encoded .= "/NErjXYyMwNCovU8DbJ5voG6PBNPtZ6dliGTiBxCbsmjjD6JtzqGzKgVoGFzY1aWdTxQuf7U3934tz//+tc/bnnpxa+dXPb6x60saX+mrn8jAJD1/KdeQeNL"
    encoded .= "Lz16z2E5vHBSpk+eLxZg1K0CmqjBCwvJCOXva+M8aEC4kgQqFHNsMVlN8MjAo1YdyGxFuBUOm0LYlDvccrOWEcgaAYmscZRxRU3WkdmCc4FX3kcG8iRTChsH"
    encoded .= "g4gVryHxxIKcpLGEqiXZwFQ9FyEuLFkzVfCKo3/ZH3da0nzaNE+sbQskIMj83EAqG//UnJC0qng5mOqArTqYEZGZYty8eHh61jQpj6lvYQ3AtHTEfQ9g2thy"
    encoded .= "KmCyCB6JhulsOmC+GN+4xPhdz3/Fxj+LJwCVgs/s9Rk/FVgCIcRPvYLG3/yxrW+ajpN/mEymTz62mM8r6hJMU2aiyjI/rapAgAlMzIENILLPx1UAw9xbAQ8S"
    encoded .= "4WTS+EA82yyxZaVhqcw+95Za6HH9jqmF1ktVnJBmqoHQYVP8vErB6QdWbzMBRuMWM6Br+m1gMABRH1Bli0SiBBke+QpFlRgIdX01MLZ2rO+kEm/xCW7m4fIc"
    encoded .= "eXm/Zx3ufhvd5N21G0Y2SxyCYFlWDl5ZBtzLMBrth+M582gagMjeQwNHeUxiODJ/AAAl6rVOcNQ31MrjkWOL+UDDYwaUN/3gVx/7XpkGEFuQ8DN5fUY9AAl+"
    encoded .= "0PjiF/N0du3WL2/MNr7l6GIBrjwvjEkWiizQ4ZrlAE8MOHXl3R0vIZjZsltARyLsGghLI8rZPCMG0Cpx4Xd3Vb/PUWeOr9msAqBzA6mqQj0bMzQU7ajhDpCz"
    encoded .= "5pPyuGuavAbjVw+MloHHpvTNZXP4vFbRsKBhnnkVQFRlPIynk/IwoYK1f3GPc+fMaUN4IdkjCj6z05Fddo5vE3/Q9SYuiYVEH9z2at9qqsNbzhUlAAiFz99x"
    encoded .= "3GT4mqF8QyjgJRNPZtNZ2VouXs47bv7mn/vtMw9fcgkPx5OK/Om6PmMAYMr/wh85eJc9deO3d2zMnnR4Pt9ixjDAc0xUyDkCQxRDyDDrL+4ZmeCmQFQTjdf6"
    encoded .= "LD7Q43mtDNbJeqOssIKtU5jvRVumBKReAreNGL3mclr/0Cq3K017I1XVAlkQqonGXX0BpNL3quDEnUJFbMF6Sfnr1alATpiipLDq9zbedlJmTvcykDozyb5D"
    encoded .= "c29FsSjoi7bMZccKgDXI0N1uuMsdkLqyKnCxjaB+F3Mh2NTPvLPwPdYAqbDQTQYxxulsujEfxzePi/lTX/BHO68zXcFn4PqMuBzWof/5nEMP3IPNN06msycd"
    encoded .= "ms+3iDEZuFlu1kvcNV/O67QhI7/fN8UyYTZryTq4ViyX8XrNU4j6OFUsz5ELrCWRh/y1KwKt22/P1GRh43IPtvtplS7AplnqpACvpk1TZpbpRo72h5ukINr0"
    encoded .= "NX6LQlFDlHGjnYYFoStusfUwTcHswXVc4MbiJx8d5rpnfrTgGOQrQCQFbnrH8YfRR6nrK98nTHbj08SiOiVPY8GI6Vk4XZzLFACTxXyxNcXwiNl04w3P/vIj"
    encoded .= "j3zqFTReejFP8Bm47nQAuPRSnjz1Chpf8p8PP2JzsvmaUqbnHVtubYExJQv0Icmlm4qYhwVDE8wq2jMk1lbT4DVr+rneJPjmZbglb5RH63Ghjf5w/pAVwyxs"
    encoded .= "1QAT06pCJMHg7m8HsFy9f5eknWQpLwQ8PB8JdqpaJlNv7VXvU9tn8nJdXxNYkv64ViRmJZ1p+6w67Mtv/Rf2pM2VO++nBf52nuM8a0s2VtzpaxQ+njWwsFWW"
    encoded .= "hvdWZ+1yL5y/Dof+X9sH0prDexU6qel6ZVBlTOeL+YJrucfmdPYX3/9VR59w2etp+ZkAgTt1CnDppTy57DJavvg5t180Gzb/ilFOW9bFFoEmVEUyGdBoWUJV"
    encoded .= "5aFtWOGa5oOq4OBIgW30LCuKalF8r8qfQcVRIxTF3Vzu6rQqEHVrB6RYAwbhu3gATN1xf9bm0wCISrLy4RUY7AGRY+DBPI7VBRPZEUABo1ofoa54mnage6bn"
    encoded .= "e+Zl1BFX7fjhBTiULWfyhfeVeRgKYR5LNJRWakwGbCroHhA5uIRCB8+soZWYR0aqjEwJuVi9AqeZAApGI49OM3HxaUu/ctFzsANKo4V5HCbDtBTcvqzzL/nZ"
    encoded .= "V+x8w6UX8+Sy16/ufP10XXcaAJjb/+vP2bpomAx/xpXOmo+LBREGO54jCwQQzPYUTfZx1eUVT8lBrZ3SIn+ISnOabfOdKr+vsYdsNW5gnnvnaBG7Aq4BAQMp"
    encoded .= "p8lnj+4G5whzk1REpmCcIuFSPxE6T0carERpo45WZNMaoySTk/jVeymJjJhWsAXwVuuDKpj3hmMubokzec5m/bZEaeMAOKYQTcJOJjCPIyXVs7m388SKd0q9"
    encoded .= "2tUGaL2sAzCh66xjkPXLei73zOUx2EUMRX/lbll9BSigsZQyBdVbtkb+4v/xB7M335mBwTtlCnDppVyeegWNv/QDB+6BUv6UeDhrsVwsBqaBakJXiCtl6/wx"
    encoded .= "30pLRkASdgUFXebxAWoKy9UvR7kiMukyl1kA+e2CqD8i/OT0BErFtCCvR7eJRtaZRJrWJ9+Ge54o9vrDJY9vmFvLa/RWIhR3qdFt5kkq0Ljh1IBn346BrzHO"
    encoded .= "PSbtkH1m5wCp1QyF7wy48jnT0QUMKbnvPlb4BJf7FS0gIikca/5D9nISd5pV9wSs0gHzMHIKqnxHRL43w3lAsbzr07M0/nckp06PElWBYazjAjycvDEpr/y+"
    encoded .= "S7YuuuIKGi+5hIdPxI1P9fq0ewCydx90FrA521q+fjJMHnJsvjUnUDOfse2v7mL5Lox2vTgq1n9MAJN1rK6MSWkSaPhzJgicBhVtfdzUn4Q0ZXrEzsBgH+ta"
    encoded .= "uzyVgIXt/qob2hsX+zNwxOhG0o7EPwBF73uCj1ZA2k+frlB4K8br1fbJx8OmTnmjkdFG1kDqk2VpNisVSjaVxNM8cM6WNkjb3LF22IJprQchvGgqc9ataLzT"
    encoded .= "FADtuK4MJQ0+W4/zZqF4gBOf4jYZfWb6u8Z7+4CVEgjwZCynk+ls5PHdKAcf+dNXnHxQ+fIJYXG716fZA2B67nMxXHYZ1XJs61c2pln5TTniU2bIymaaFeUH"
    encoded .= "fO3Y/sxWd03QDcgpsRT1EtDtakFWnqg/mndvwgGCwMXUBL5iYUDQ1MxdZWhlwLyVhpM1QKuieDTfk4esf9AEn8wmLxs8Cc8p9QVBhN/PaKgqZtuBwdnNziY7"
    encoded .= "+pGBukW6TtB1ikJJpO2OPJKW9pi7sc0ZiXHPq87NNP0x8KKmkE0BiajTiDQ1Y4O+Vm796xoZovnZ/AMkUhg9exr6GZjMF4v5pAz34+XelxKAKy5Bwaf5YNtP"
    encoded .= "KwBcfjnKZZfR8pd/8NAP79jYeObh+Xwuab3c9dLQFg7E3Cko5YF3yxpj0U8V4qKujLbY/B1ZbFY/q9ZE2rApEiEi6m1LEoagvLsWsXxmP/FkD2ruPhO5pXYL"
    encoded .= "rvdEqNgVxvuS+YFIazVw6qcLK22npc8sk8YfGxix4MVmDVqQcpZ08EK1Za3X09WdjOyqc+TLjwxbicneW65Jph7pnupwO9nK5rZTfruXlD8HIAm6iaibJtp/"
    encoded .= "MmXzSUXH6wSQGYCBDCMKsq1ss7Bhcmy+mM+mw1f9wFfOf/KpV9B48cWv+7ROBT5taHLJJZcPV1zx1PHFP3Tw4umw8zUjeCTmQpWLCLtZnTA5waw0KImi2khn"
    encoded .= "oHG7j1/+6V3PdSDg1stSSK2+nJfOoVAOO0zq+rcILjpUGLVSuN5hdSVo13sD1OXHp8SaXDdiTik6EucDaEOuAPmhPIVpMgm9nnQ1mXmmfJAMSs7eU+6ADUer"
    encoded .= "xOaUh8lMPE5eRtO8/uOPaP8YYakNTKIqiuxje047G6Akg9MHaK3ReNSplvuUaOAIOAe1rOcfZrcJCRy6wGd+PCm2f+3Grx0Xn0GQs6cOwzAda/2C5//h9C8+"
    encoded .= "nUHBTwsA2Lz/7CPYBZ6/hSbDeWNdLgqToJUKiIxLu+xjqLrOfXfgcIuFEEDmBjdifT+Y6oLV1E3+q1FmBxByuvKhH74EV2O4gmaLAqf6Oe47xuWYAVr56Gm0"
    encoded .= "Lc6+V4Diu07t2+BZWh6V4qYIhLz20OdFcmZIibryKUXxVCIoKa7jCdmoWqQ/FAQIOsKNTzJh3kwDXkKDTK+p0RDWjtvc2/EA8NTsFoK75UO/bRl/3NbRqUjj"
    encoded .= "wq/UjVUA0IfcY00IcIfKpzykKFgHGobKfO3hnYc+97T77Lvt03XU/adlCnDFFSiXXUaV67Hn7tiYnTculvNSaWjmm0wRJQXC7XK0DYfe5m0mHM32KlKqbUdI"
    encoded .= "o+ntRZwFxiG+sYrw5JlWOV3IKK2/+yCmObv+pmxl0leReBMurLXtqx9rhrEiTuvJz5jI5W5zhaQ0c3gcLbBSEjjjNEOD2V51noq0jLRfHC5xnq8gGdkkkwzN"
    encoded .= "R/D/kkolZQ3uh/JnSp2/KeZAHEAYvBfvyunTwr1LHwDFwRcmd9HDre9U1GS3RwFrnWQbus/8/GvqO7WSmpC55mAUNZflWBcbk+HcnUd2/vRll1GVeMC//vpX"
    encoded .= "ewDmjrzsh+cPH5neOI4iccyV2BAbsba9gqjGdONuMl5uhQC3+IRw9VwHbRJuf1NIlZ8j5/WaXYLP9928IOrNQ+tutW/26QsoRrkVDS/C6SydUKQqKgueGTAy"
    encoded .= "AyOzbrCBeyBKfvzmqMf/9L+zj2BtZwvOKHIsOqrv0VWGJeeA86AkEGlOY4I93UbMnc/pLjXfUMsTY2H607c/I5SiOd+Pos3WE0LQ2OUTkD/HcSfV6ZVlvvd0"
    encoded .= "wvhtKwJyWlL2LKh/LI25LxaglbeCoDm3xwwUKiMRJkB93M/+4ez1n46pwL8aRS6/AHz5JZcPc+bnl2EykYgME1uEDzEQvg2z4Uw/CHLLt9+miTfb1tcMGpm7"
    encoded .= "+SPl33ldWwctWV/JDeC+FhciJ8HcO0bqWwBLY/FzTUoL2XP6fc7TH6seX8629Ti8leZ3BqMOZMIwRUDRPACrLdbyC8Yq5+tbboSfu9c02kk95XvU3GdiWWJr"
    encoded .= "wFD7ougUQ0N9zW3/bHDMYtqXMNwj57m373yJWD3HY25p/ccCjN5msvr2UH9sEgVN3nWyPqVkppZhd3i12McoBb7EYXSaLsipU4WWIz//0ot5csEFYXo+1etf"
    encoded .= "BQCXX84DXUb1tnO/7Os2prPHzBeLOeSlC7AoqchfLNvYgPhSGSOEMwv2GiEHAzwmdHCl41CqbIFdAUwYWoHJvxl5rzv8eYstSKEAsl4xIjfc1az5jO4J379g"
    encoded .= "N5Q/Iwe1q09ZL4KcfFJu299AhCzc7fsR7H5iFkcLDR+aNmwygLQaSMiakb2ZwPYW1AIUEr8aDe20zJ5pQKjV7hxsXodfq+DG7Zdiv5xH8ivzJ/UhebhNPQ3P"
    encoded .= "cs+BZBf9+zzlFUeXia2SnIfBPCyXi8XGdPaQQ/sW33PZZVQv+VdOBT5l9GD1zV/6n2/aPfLed0yH4Zw61hHUvBciKWc/8KYuyf2qMXC+WQfJI808ppADS+f1"
    encoded .= "7/QhOwUnW5uM0EnmE01wi9NaI0r1J/eWNTJPnOggfx75Ua3fluhs5hLKYsKSVjV0c1G4t1Gh000dfxxEqHWL7Tvu3OXMWDIKoj371nO1cv3pnEDnUAK2sL5e"
    encoded .= "C5pEogyCGcAyHVkAGsIpvtPfviSbvIU+CZiUAblEQ0Sf3wCOAGTLrVQu0dP92ZTPN/x8xpgQmSx4HywQq8wnBpcyEKPeuuCtC37hT3bfqH1cIet4rk8ZPZ57"
    encoded .= "6esGImKUPd+0a3N27mIclwyUPJ8xxmWTxZVXTpVxcCBFcM5BNqh72oJIPm2nWbv3xikCYoawabG1JssTYORkplN2OuUHACoN3YbcphmU//b+hPLndkXoyRN/"
    encoded .= "fMCVfzbtyO68f05Kvar8QZe3b95CcmpC2YJv4ERz08nw6ERcs/Ya7zhyEBIPmjyG1IdG37M3wLYSklZSevc8P1PtxKM1tDcE5l8c/U0A5QXSaoZbfk5PW/2U"
    encoded .= "nktt+MeeR4o3NVn31uCY4SedVlkZAhWiynU5m0z3T2jjWwDi516MTzk34FP0AIQbl1+K6cFji7cPNNx3OS5H1tOaIsU25nzV5mYVwbA0nr3FdblRwQWg5+Vr"
    encoded .= "/cm99d+NJey9AhPYFpPzFljfrYfUtkto64LmdhsavH2NeptlSoInVWT6yJmQ4SYrXwBVQ0bTjxUvqLmya46VCp1WtULcAJHWEJPdpq3GOjqBnedibWZWNuCa"
    encoded .= "QJxaL8iy9DxxjIPGxPCV4LD32bDHAWmVL5IN2KsDr5TLjDfu+IEhGljMMS+vW/mbvd4sWq0nRv6FBTwJwRcAlWgYKo/X7q3T+1/2pziqz62M+ie7PiUP4PLL"
    encoded .= "UQDi245uPXkyTO+3WC5HmPLDFDisXHNSjvbEk1zM1fVAUfpsVx5ARBlXqsTMrMxhBdqBZTYBhz/Yr21nC+l6mKyLF1T6uKkbGLu8Bas06GSfwqRbHfDYd9T9"
    encoded .= "jSTV6ji6t2P8yHPg5GKu+Ov6Z2z2X6MoYb3DhgsJpVmeuwP5SwDR65jHTjj6gzX9b8lKMQjrszYkdLX0NLqViGKYwq6SzIlvSqErfOu+JO8wyVweTyAnKaVs"
    encoded .= "weS9ZH3x3phldA/AaSljXY7TyfTcg7P5lwPEl36KXsCnBABXXqlkMn27G+KOiSsW3KKttmnG025jSa6xcEywl/7kIJODBtRU+GaNiOjml0kCwVP3AmADlMp7"
    encoded .= "NmAK2mUAyWmcLljJHdeBrZDz92wdv7IE9kQLyIPIIRsZ+LRclrHEE++L9cf53AYa7V4+6YYy7cyRPpvX1q24ebzK92blBlnk279Z56lN3oIvZWa+d33q/m56"
    encoded .= "mnC09w6dLk9m4DUNcF5SattxBQ6QX2kfMT5gRovrHGPlzbIzkZH+hvLUDYFJbX6mpyv9q2MRBoi4VoAX+E8A8NzX4VNaDtw2ANjLDH7tB7buX4g+b2u+GOvI"
    encoded .= "gzGiJrIZDe/QRKLzvN3Xeu13zL85QWA/T/exhZStHHNsGBrbd6YxeUMM86pgNhmFjI7pUo4olY/6shT5WHd0W2OUPmcBWNl05G5CJOkE3wKwVhTIASUYlufn"
    encoded .= "IWOcU++7KlpwEOezK5SnBNYm2XQh+rLCgkRfk4WIljcx91aDoajqxSmUw6dvHR+MbGZIAlECpFZIVUTsK6cxQV7al9BYc+eF0iFzlGxuXK7DH7IulNYz82zC"
    encoded .= "iLOEF6j0Vx6Wy8VYqDz6e79i68FExJdccvm2vYBtA8CFF6ocAE/fGKYbqHXkzAhfB28Fyudnnkqrg2WWPwlEk67i97lZIgwLyE0Zb69xgdMQJrfArXsSNNe3"
    encoded .= "/J09kgUlrR/XGuv43oyWyzjuHkzqlwe9AHjuRNembQqqHP1qwSfKJo8R/V8tMKvHlGlq+kigZgkqaMmJVzHGmW6KxChqd1a0SpN9NEr9yC5IENcDSQZe8xI9"
    encoded .= "WchASNsk72+i0Y1A1G/GqdYUA7Gu5eydxvvr6AJSzkeSQ05gl117pdV/A7YQCEvhbr0k59s4LZMpL/FN8vcl2O7Ve3PHcTG9+FvfOsGeB7xlQpMHLJaLJdtU"
    encoded .= "0EsYcunAAh7Jt/H0JRDtpFFDyIkP7LxqoN0VIZT/jve4I92zwYgsu9Z91c8ZZLqBbQWANTlJPB8Z08apaxO6OAs5e30h2OlpBwoK9pjAGw8M3Dw4lwDQ6kvm"
    encoded .= "NO0jQt7q0mbJUarAYgc9SzmxgaJ4IHhiVH4yzYUbPgRM9l7Iyg1XEGuGYn7jzXFQaS5JJkVd+V62uJnnCIfkaPlKzGAL9iH1IehAyLb3Fo6LlKy/l6LmF0wY"
    encoded .= "HGyyl9LJJ5hBRLXQMGEery0n3Xz/n/vtMw/Ddq4d57UtD8Be6lH2POABRHThvC5GgAu0cz7VarbVZkmNH2GKIKQbGs59boU5iVwjdFmh9MFoy6xKft7dMkIs"
    encoded .= "ZwXjfUoB9uBlxAV4hb5qxsqUlrlRqCyXrNrH+b4DTZqSZGuUzLMbjjBJa8cp9C+7oMp4CsWoOQ5j8RRru7HICKKdn1EmPyNMiTI114fUn0St9Mnq7oKsedi9"
    encoded .= "x9z+m+gMfifz2lVgiu7/OmvY4wrx8hAWjqdc/hVoC0cDdoIQAZ4jQblPiUjK3csAquX8Vko8c2iTvJEy1uWyDJNzxoMnPRIAtpsYtN0pQAGACv7S2WQyoLaB"
    encoded .= "h2xRGsHI2X0KEPa2mmxwfA7fCFtSgBUH1xQ46hBFiYw3d3U5xwvuoHeNtkYSUU19attJdEIP52CNRVRuyG8m2q2kaj1tSqpXy0k5kDrAZNAV950fsZWF1tGa"
    encoded .= "aM7A6oCd2cA2d02KZs8lw+oYaMlc+tndF2V+/wq9TgO6AaFwpQG0E+V4xJ4iVUCRjPWDzMohV0JCmjZkXydDTUtisDoY0kyFLH8g3RPXvt9CncYFq38HsFmf"
    encoded .= "DDRyPgbqQATi8mQAuODGO7AKd3Btq7DFQH/l+7feNCsbj5gvt5YgfRlSRmFVbHfBLP1Ufbeq3PIAOJcVwcsv0DBCGy+A7bwA0hNxbL+8lG4y5thrBTvn265n"
    encoded .= "B4IRb7oZtW+Foo6GBkSfzDWzwVlZVtZ2zNXN7nAAhdLvn5OkArZzp5eR5JJnfiXBzP6osQDsXhCYm2Oxmk5mLUhz7FykLxa0tanL2YQ2llTB1mJEsXafOtBY"
    encoded .= "X1aLS/2oAMZjcLxaPbfdTTtEssmfi+IrNUNdb+cfce5M2rCUyA8MI6Da+U1Bi22aZu+J7UCNvq/un3G66lCmk5GX//SRzT946BVXPG1MkvVJr+P2AJjlvbMv"
    encoded .= "+dHDZ3DF/RbjEiANWXAwO6y6DoHnvFuwKaEm4EoTVko++KzBEbp1g4QPouhkE7oUMbbfkfuOeD7nAJjymctlNBmlSsfIsrZvWxGyt9JMV5J1WvF8ON0XXxRA"
    encoded .= "XuO3oFwEp+z9iI2l8Ei29THehSg86+1fKL79iTQO9jkrtQNEowCN+rXXGoBBw5f4xJl2Z4wzHk3Q0GXJxsieIZjX5G+RddrWBPcA2B57otKAUgXWBqM58Sb6"
    encoded .= "GbJDGcHT83093nPmOPkHQVccGhPA0q4qcZKJDF7ih1UeQYT73BNPvivAuPTS498gdNwvHrjiqSgAxsV8eODGZLZvuZwvASo+0J5SaX/KPelDuGS2Fs8wK68P"
    encoded .= "rHXbwrMw76G1lIGeUrfU02ew5YzEprokqIkML1FTW40Ar5jZ9k8bSEr0Z+BrrkYPuRMabpU17JX2KzgXleTkFfi3jOR+5suOWqfMI3vSKupMttFqy1VGhb7i"
    encoded .= "2PM0Gpc3xrxhwhpblTLeEGaf01QIsH331l7wgGTOjU4BKf+dRlPbD4lpWoYfdJK+zzxoWG9/2tHx7gWv9hE9H9ZU39St1Zqc2JFxUqouZ8N093KOBwL40FVX"
    encoded .= "rR/qdddxewBXXiCVDiM9bDIQGFR7YW2mtxnhYff7dWyh36xoUx3FPXt9dwL5pLxe2N8M7N/X4IOsgYfFjWBfOnXH6OSIGzTCYZ6KjnQeV+tTDIxZ9ijVbPG1"
    encoded .= "utPco5eRtcNI6b4qAExhjCZm+FIaNZDl7YenEvBAXlcqqO1QoIHcoqTctgqxhl4PMBpPcv06Lw5nSDcXNcttQUgoIoWy6d/Zo7N25T55+dyn6Bpr/4wIlTvn"
    encoded .= "YchdP4dfvcITNXlveRE/XhTQU1ksGA2Xhew1Ii29gru6GLUQUBkPBbYXBzhuD+DCq9S+FJynB1USJffVLLuJk/e4Yw7DOsOw6GYu1qN/uFLJnjnCkAfbwtLZ"
    encoded .= "AMLbk+cjLhDWOAUQm96GNtpgZdtIWeCQ6aP2d2cdci843+8VLZUl9XyEbZE+bK3E+YIqeF2P7Fz8lcUhE9DcN6cl7cKDRZypqdfuIx5XXjSqJeXMtTfAAmCH"
    encoded .= "KBp/bYmt2T9gzHV+kJvBUBbpN5iBknMMOqGyPjYAxEnp4eAXw+mDn+hJPDTD498a0KPhNyPRmO65LjgbOcjNcqH8agO2LSFjBWqtDwAAPBYVr8dxXccNAE+9"
    encoded .= "AhVgYmzds45wqkMcONws5VROvc1ymeeWrmD+PbXomOZyfVQtexcNkHhOQK/Iab7NMTDuyibkrakfMULWwUyDlWtd7U4Nm7+APJjUlOKEACnIHLWYwjgCwANR"
    encoded .= "SZaU3GT5Ups2j3QZ92rJFyso8ZKNGB0s9wY6OxOZho1t9vHI5/atXE3d6V5DH6KMjx9gm4NWqsQKiZCpS/4ijVAeXurGLE2rOwnQdvRfY56RngAW+aN/WYOV"
    encoded .= "pOOf5TpOstX3Dij4NfIOqhUg0LmXXMLDZZfRiFXIX3sdFwAwMxER/+r33bp/yTvOHWsFc5xeZFeTj2GIlxVdO5nna4HCMY8z670qYatC3uhpENx8Tzqywm4d"
    encoded .= "cBMiBRjPXIMl9lhcgLx8eDuG+VkotA0N9DhJuRsKoe4NaZvUKT1bH9ja6IDPW27v2z53+6bRRc50O3Ykl9S8lgCwXnnawy8sI7Ab4zzOiQAqlOrRfjmirfbF"
    encoded .= "vDYjMvRI+6hy5PEQ9xrYxap9Q3B4AU2zHS+8GeK4Z94trXImlDEMor1qvH3zcvQFeuqy9yUbqV6p8iASvHyeAhMT1TqCCGfcG9gP4ONrwW/NdVwxgOc+V+qq"
    encoded .= "tHkaV+xf1mXYlWShzXLWyv5jSUE9kkbMfdUSgpv9G+EN6I+8DMM23LTR+/jMzfOCzoGm2QJXtlRelrP4bKriQprpofip7UCw1uXob+63bzaK/oeCGP19ogz5"
    encoded .= "vfQuNThQNmvWVgtCWeKLBhDF2rTKGL8N5bhztsj7xCbs7D5EU84OxoyEmr4uK8ouz869zug6ghKatXqf4llVxo6VdflYTuUEgFKmDTm78nVyZ2jRgHQmkNtn"
    encoded .= "mhW4doiCzvT1HXp5erc5SZrjHAsbV+UGMY8VjJMPL+enA8BzLz0u/T8+ALhQo4pUy12oTGYM9umo0Zsj5ra7Lnc+NrmoYtYYHEvMqM16OiErMbiERUVaDYCG"
    encoded .= "ZoInrnzICge41YkBJiwVTISm2EnY5wn0wBx/h9Sa9VkL5N4PBKH+tHwptMc81mNhTYVhMWKXovkEImG9HNozonDkimerq34gaV/Wmm2mPeEK9XkZQSLFPetk"
    encoded .= "FvRkrdd5eT1rLVDocTqbSnBPQ+qFL4WanLUgiPSKdXs0pVU1ciaP90ufaeku9z1fpuENoEWS1lobzZnvramCVtfwyGohqmWYTAemUwDgeFcCtvX+8QUvTplN"
    encoded .= "phgrVTAGtRXhBejftHYXmIyYBW+cyebb2bJhEvaotyB7DJHk46ODcAi1HlDsyOJOSHyORc7osHBGrWigKyKlPIZsAFaHIuhPZW1+bYJr3WZunzUv0ZOotKv5"
    encoded .= "zPpcvllBziY1z7m84nU2OzjZIHowTOhtomdtH/wR6j5Q8CEnyDTQZ4qGWDGSMhYPaGMqBCSl1N9ed7OroE1oovjQYnuYEQ/Mpa6u8CbXnb9o6iTlW6h6sDQe"
    encoded .= "ynWv2BPri+qDrtOEF+MrKMrjylwGwnIUADje6/iWAXWTEQ+Tk4Qo05gVlXHSZQA7S9Apf5v0QukeUDnXG+ZDnqXwIlhNA7WIbJAQKB4Cx9CEHiTUV+tCiTbT"
    encoded .= "qQClUGhOZbLHEPPp/J1yxXSRAHljpnPFf4cA5tV48iVTynxVhffluwZ/KNUcrfRmgXKxJFz5qZUttKkWzo8Ftel50iAlNeWa59PT+eCQxnBq+35PEchZ4UCe"
    encoded .= "ZC7mf40Ccq408wKW/x88cPaQ9aH3BMxAaGlC5Cg09HMc+wYOGV0ZkI5B/e2MOwnUAbBmq54OHP9S4HF5AFdeqe1x3akjFsaNswBkwUhnw2XjQYG2+ngnXDZu"
    encoded .= "DS4m5AuhsVpyiMGEn8i8Dfsc7eUIv1hmsa4WtArMXr9MaHLlvWCgeRdBA1ocFsqDSVZnRLRzi/58brwTjAKV9Rq8D5ZxFgxJ0AHci/HpR3alk1n1cSRByWYx"
    encoded .= "IaEUJ2+KKPfV7ltU3OrNnGzlMyfz2KoMpf44SBitGmiLWHfiVxonZNqNu9yWsbhCO+VKz1ogOMl8XpL1whQy08bfbTw4QEpBw2g02XA14DQG1o+EFiESDgf6"
    encoded .= "qZ6MbVzbmgJMMEzWMXQVsnhl00crQB471XGLkWqfabRdvqvteiiA5Gmk7wieEdbU523KZ0PuxipQsubSwEpPWnhSASaKwF4aaAOa0PSgMXCPU5uM8CiSYhgp"
    encoded .= "yrPwNvpLhNFtGIfF6Ok2/obzEJ/YBDUBfMsJbuoxwW+sg3XSTdYqvdKNAosFmcWNKYFRzXEWgUmNm1pSEOboZLC5UZF4Xms2HrtSspfwLFamJA9WyxrEcPlK"
    encoded .= "90kY4+QRt+xxfmdD2QgH8lFSZH21cnlQy/b2920LAMZaSzHBZvuVBtQArkPidUm+jYXrrUEjqWbJOfSCU7ANFEvUViUBjQ8G6PphIDHr5J58gE25LAin4Nas"
    encoded .= "55D3hlO9Xg5o++lLfl3ykeGVWW9TjsQ4F1MyAZW7jYXIXcxk+i2jKZWl9eNhZp7S05mOVZzJgGbsSdbB+2Ry3oFq108gsRgUR5YxmrrIz5FIwTRnnTHBuaXy"
    encoded .= "klDMGzJbZH8wzBDEJ+1bDV4wkb+je9TgUuMhIRkaoy/rcSqbQSB4YYDJzjf3fyj+pq4Oa7HGKvRxXdsCAGBcsVDgGNRmLztnQhupWL06ACWg6YUMlKFrAgN9"
    encoded .= "mBNHwyPhRJu2W3XZkFIdNiA5AcPbzZ4B/KyoNLXUdpN91+ZD+dq+s9aT367bAL3+a8HMO8jgj+ccuHIdFjLVOqyP7k1Y4lP236xcWnNvKrbpivGA2yVP5UMH"
    encoded .= "gVK/9tWP2nKBzyCWZMoA2gCkRdUEAj3Os2N/Ur/WQib62kQy/dB5f5SmMjbNk/dcSsvcDKIFesNguKEL0x40ZJAz8HKyk9do4twKXfwioJorwXVbLsC2AICp"
    encoded .= "jKFQpoTGsKxwicYG8WLUbID6tVkplSLPzTooeaU5h74632IenCOmIax9BFh5pv/kJTwfMyevm5fbc+BYcrIsJZVl6ty4ZpNSEgpGjD2vc+mtXFL2O4TUmHS7"
    encoded .= "JrgyKED6Gn2x/hO4MsYlMC51P0WNOSlr5+w5i1EMA0CFMBSgDEAZWoHm2i1hNd0O5W8OzEgy0nUs9ZbS4KTEJYrncnym8T4SL3NzPmbxASGx3DDalD8y84KK"
    encoded .= "iJ+YXJEnFVlD7upbUwlcHHwN6HIP86DXDA5KLyFCLcd5bQsAqm3BR2rFkClAr2G0Wz6u4j6Z8lskP5USg0LJ5W0q0jturyJbT+9kxQqBMlCxCjor5e8EbD2A"
    encoded .= "PkHDrGXyC5p2vR8OkEnhGZIQg94r6sYqz+eo73cSGrYlrtWglruM6pXYzIcKg4qsJoxLYDmHTEEKMEwY0w1g90mEPXsZe/cVbO4FNnYwJhuEodgZecC4YGxt"
    encoded .= "AUcPAgdvYRw9DBy6Hdg6AiyOiNIPE8JkyhgmOiVlAZmm35R5iui3s0IBvHOPTHlKaEo8yOkzqM+fynYrPFnqfCxVxphgcNMMd58dh6z+NcvZ7eAFXSsj3Ezr"
    encoded .= "VPW1zx6zUtrtyHCTLZNDaoXzk17bAgCqg774Swn19LjeI3Cbk5igf6UNFplH1daozXqkqLQrd9pi7CjYQHkCARa3yJNkjFFJ4iJnAAmxrfIUe0BqwsAkC2wC"
    encoded .= "Fe7KilBkQSU1xrFW0Ihgiy3KU3uOkvLrrXWyr02WQihgLBbA8giwXDJmG8DevcDpdyWcdS+m088h7D8d2Hda4d17gY0dwHS2BpwaAuW75RJYbjGOHCbcehPj"
    encoded .= "wPWVPvYh4PoPMG74EPjmmxjzY4RhAsw2gMlU+e7JS0113oGA7DSmQEKztMLhMqfPUDOQUTm1tcoDtukpjx+p7DQtW3E0I22rBz4QCr9Wzl5tl0HDKUpjb15A"
    encoded .= "ww7Sw0xycDDay2c+eHe3NfuXa3sxAKoFJN5hsdN9W6qDIR0Y2GAH89l3quWrIiK92W2Sf+9AURLCmn2uFLkEoYPU0NFMKSqHIPhqQtDuipaK+bJao3kIE+M8"
    encoded .= "6fsDRGBwNTmnKaZlBYuE2b5HPXkYNmcug9A1LoCtw/L9npMIZ11AuM/nAOfeDzjtbNDe/Z31VIQeR2C5CFRJHBD+EoG5yry+MGY7gM1dwP7TCPe8oHhPjtzO"
    encoded .= "9LEPgd//roqr3w585H2M226Rr2c7gMlE7cfonYx+OllJBfOKQFYon3uHPFI8ngCcYP52ROOj7rycGGOfEBamjJF3YYHkqIu1/W71aUX44XGRAPe1ohNH5hOa"
    encoded .= "8aCi4GWve2O2TNY7Lwi4ZNCgRFUiFl6asKS1fc7EUjNQ3gUL5nXWzF4G0nChV48WmL2OZlD75yISpphl9BZ4MIylH/J3srQJah3ccippXtC14jbAidYmC9Lp"
    encoded .= "CxAwItYH/lpavDxLjwqJEsyPEeqSsHsfcMGDgAseQXSfzwFOObOtbbmsEWcBwz07tWxkmkRu17Q/jFIsn0B+LysArg6oRIyduwjnXgg698KCz38a8S0fY1z9"
    encoded .= "9op3vJHxvqsYhw8SJhPCdEN5pBuLfJmPlF82N6a43zhfztk8FTPXuYNWguFceIOUvvKB4n54nA9tEcqDmYenvZE1GwBKSjhykFNvlVNMiX2I06lHATrWQHZs"
    encoded .= "79QpwIBiBhJMQHGUjjb7zQvSMaObEctscIHKwh2oCFU08rqalF6/ktJpvbZRqLEQ9qX/YhcGE1xhtMOWl8tj5yKWJDDW5BEjZr1Inke8rTj6vIpXLZiFzIaQ"
    encoded .= "A/CAIxUAlXD0iNB0j/NAD/t8wgUPJz7lrKB3uYR6OWJ9CgAu8X3iUvAiqYXrn7o/Qqp+VhwFWzINYdRAojhWlU4+nfCwLxj4YV/AdOOHgXe9mfGWvxjxoauZ"
    encoded .= "aVKwsVNaG8cYx9xwM1lS9hnQgm1ZF2imiIhEKwfMzOyVpcFsleOB3KaafjQXNViSriA0DjkhB5TGOBjmULJVyVpkiYkRSyJj4szbO+h3e0FAruRvmGWbcrTM"
    encoded .= "CtgiVzDTdps1xLzV5uFJuRMj7FmGZe+tZ7PQppMPa94VMbuRLYnw6HPyDsLouJXXhDgkkppBsFN8m+yvRCqltlwQKWrIQuohlq6/Voc9ZJmOR2+XufVFDyU8"
    encoded .= "6kuI7vfQgmEqMLhcKOsLPOrv9jxNTDtoaS6CQbzFH3LfOAohxizrSoFYtOUSbh1Ouxvw+K8mPObJE1z195X+7pXg97xdTmza2Kn8HRObKFGSgrH2LzsQBXja"
    encoded .= "gLXR/owcWZYMwAO0U+3xO6FI5/TFtSJbgWREsqcle6lW1vntMhNmQtoSoXBINlGwvIfAlfUKcgfX9oKAXKox1TM+U08apUvakpeT86uj2TpmmtEoBrnye72J"
    encoded .= "4au8JwUlbtxTWJUp+8qSQ/ozBK1sWJBodt2V4wTa1eirWZS1w2FWIcF7djC57WzWtUIAF8bRwwSqwEUPBR7/tIJ7f440PI4Vi7l4kWZNetqidlMlhQBmj4C7"
    encoded .= "X+X8MLDLAmzCEN1oZ7bxncsLs3ojwDAjfM7FAz7nYuDdf1/xVy9f4t3vIAxDwWwTGG3XObXR8Jh65V/BaFWzNFB5WmXgF9Mcdx6AuA93KPravLMevUmeQav8"
    encoded .= "cOVE4qFfNh4M+DZnlRlbGjSekg1EL/8WkzBs+0SJI2uu7QUB05vHQlet41kZ0ghRdNAsW+8us2o5oQFDGNo0r3RSQc5lR6sHQF4/trlrv8TH/k/KFXCSlOWm"
    encoded .= "mxztrAIBR3vc3u8T9TgY0WaOUatsPpA55KwaNwyMxRawOEa4z0WEJ34N4X4PVR4sww0uQwg7lCfOwTuIMfjmmjXTLM+tMOB0hWg0x+uXbmUazEqxCysNACpj"
    encoded .= "Mcq9+z2ccL+HT/G21zH+7Dcrrn0vsGMPMExJtmgnbUlJzo1cBA1wo9KCQ9CUDGfDZ3I+5Eqtt21wz0CtJ6GBC2rLNTJhMZMS8gl0+tGRYf1p/aDw6Mqd6QHw"
    encoded .= "Eoypfk6HdDrqGXGt37WSKmlfhYvk4oRItsmWJaYIRAEMuR5z5WNdPMAnpXNkshrlDx5Tlp8keMjyE3pJVk8GghREM4wwAbN2qLH5LX3VmOYcBYhx6DbCaWcS"
    encoded .= "vujrCA99IgGFsVxYfUzFNhiaC+RSFzkIxs98JSwOiijd4Hyfk1veVuK3uG2jknk7QY/xsCgPlwvp8oMfS7jwYQNe/4qKv3y55Bls7pGzH0ffEdkOiffZI+tr"
    encoded .= "aON2jH1kU8dtzNygr/gWbeWc+YLok1lHX7Ew+UigY7LvvDf7oP3IhqcHIqcs44wGv/y1A8d5bTMVGG5BSV9aJ/2wrLEkLaaEgPfEy6TByFMAe+tuNOQQ4vdG"
    encoded .= "/zJ+5UuNVAKIpIF2HjxxKK13CJ0AJYtjA9036xlYpqxZVBLkN1/JH+S/u0Uj56ncKwOw2AKWW4RHfQHhyd9M2LsfGJdM7MsyQoctk5vwOs2mkOSy2SSxdAmX"
    encoded .= "K10I2vReMpsOhJn/6Q+GxweBPOXx9jV/U+tczBmTDeBJzxz4AY9h/OGLlnjHWwgbuwmlAHVMdPnQBlCGUlJuqpUJezzpldEZXY3+SREnMZTcFbxllz+TbEIG"
    encoded .= "ihzv6k2QTHGS6XGgs2daRG4MlPxsaxlwe1uHdJmXOKav0a9e0nUAWJTcjVIGMxPOjJzZ3e8uWzLm9IyzLhvgvl5r0CLwDAci+Yp8P7nXn1GKOroNzTmpbg50"
    encoded .= "5C6m58zqy2AWpZejP95uKP+Rg7LO/g0/WvA1P1Swdz9hMZfZITURw7axXhGN7mb1y7UDvtks+ggfL1eopOidM5zuK3so1JCbD86+/I8xB2UQWVnMmc44l+jb"
    encoded .= "nz+hr/oOQp0z5keByYRAeaLLLdcpf2Gf1ghUw5uOvJUvgeAxnJXN3NulngB7P2D7AHs5PyaN0nhzApkstdz8uQK48SVb+3ekPmuvba4CCDgx6S8JDSPwCjog"
    encoded .= "GZXss/k42kV7xzubdEaQzthQfXQDA7vZRWPos5+XB9MfYYkU1/ScD6baZD8roJEq1tMWojGnw193jjR8aZ6d2/eSwg+3TE2/DGGBQ7cA938I4WnfRzjlLGCx"
    encoded .= "YBQwtXP8lMPQeVzNNLz90F5rHBch5Y4Sy3uw6+plJAtBYFRQU3HbZO8dFCJgIglJRMDnP23AuedV/PbzR3zsowW79uiqQhDaKOhKd6mjMAYCNvI56OzzAmqB"
    encoded .= "pqEXLc2RhZi44zKm9Fn9FM+I/JlsJ8b0LGXTgS7JyGStqN+wzSnA9jyAdM6fyYYlt2Qz7tYlKSezvcGv74Bawc6KZAbmixl+Gq17AUnDMikKVlGpta4NsMJp"
    encoded .= "mpk3NAFIrrFJTasSne1zMEmGfE0n5B8/VDeVoyL9OnwQ+IKnE77zZwpOOQu0mAOlgGQDT28W2D2MFWF3mpNQt90Nmjj1b4X2VoXMeAXQrRss+Sc2yARxpggr"
    encoded .= "eOvVsbx3ioD5VqV7PYjw/b80wYMeQTh0oEakvOYHKfXBzC3D/nPepKjcCpR1whmhpshnMQEPsbPVqoQ4Wl7a5VYekp5EfgB7++G5qjwmKxGvBzMC5bc5g5/A"
    encoded .= "gV57bQ8ASLYaUvOKmyDUOmmWnRHvPfO4sY+4LF+ITOQUlFDe2JBBac+/IqnPlYO8JifcoRaBvIlWb485vcpcvvB4la2fZ6VOFl8qMCrXQHfuTAIdo7ukOQpB"
    encoded .= "3N+6BHgkfO0PEH3ZtxGNlWm5AIYh3hjQ5xsYba7jVqEVtm1rSdxtCIekCI2ghtFS/lPH09xHQx8DXaxdTchK4+SZIjR4ZkuRUmqYEBYL0J6Tgf/0k4TPvwQ4"
    encoded .= "fECe9vALS58I4MKeNN1ggYMO9RR1UXWKQmHMXOXaHrDlHyQeBGMA1j0pmW+5bi+dgIszgHSAbcPAGRiAyvIG8zt02u7g2mYQsKROID47ExGgBMTcP9ksWkHS"
    encoded .= "UKfK8Ew8q69Xch9NAIWIKzOxZ+kYXGdLTSsbAL2KpPT98K5Y+9zP1HdbN4/upM8mnGu8BtIC9gwNjPkRYMdO0Nf/KOH8zwUWc5nnl9KNaSfQQZl+NhBrvhDp"
    encoded .= "YFYXWysY1f+VF2TGBinkutk8NNIpqytfkk/pbJvwRitubTN/5Y5fLt1iOLKalAIsl1Lgq541wUmnVn7Fiytmuwi2iiaTDdnlXCBLY5QaIyauitiWlSrfcAtA"
    encoded .= "6OhUZoU8mperzyf5Yhh/MhCz982BybCpUegEkD0QO75EkNCBIktvWqo/nmu724FdaWK6nTTeGGC3O6O4sv7M8cGCcvZmGV3xQWGszNkzk6u9TtpqauE99JaR"
    encoded .= "TLu2mTG4UxQXxgY8qK2Y1hQzwDO1UOHMLTcsIGAoEuA66RTQN/zXgnucD8y3GGUig80rT69NTYmr/4qjT0KPZvZVGcVSiMtEY4pSgfa4ILaY9ZW2qCrJPQQU"
    encoded .= "y/5TGnNwNMx+KJEFYE1RqCuaA5skfVksGE/4mglt7lngd54PHjZF601IKunEzhQIrngBl2ztmcWN+bk1ae/vaObuLVx5mrb8mx7OQkHdDdbWLI2542ynUk2q"
    encoded .= "SR98z2CyWtEnv7YFAIXtPICeutZ+GmNCXVrVjwEx5VBFZD24wyCP1X1a7TUAAteURpPSQC1bjTSxw0WY1RvoEhOE3iQmCPestaZJmEs8Take+9SoLBlWEIh8"
    encoded .= "lsYMWdraOsI4+XSib/tvhNPvDsznjDLRWnzw8x41QuaukBPxjf4NNjbNAgtgUiFMJkaZdOTQrYzbbgbf9nHgtgNLHDlIOHJoxLGjUK8BGCaEzZ2yZXjnHsZJ"
    encoded .= "pwH7TiHedwpo554WICINOWeCJlmx9N009llZo4eUBwBEYvEX8xGP/tKCwpV+82eZN3aREGkpwImWGA3lHmdyOJVD8zla7XQ53ZUq2qXblcpMxtMSjK86qeZS"
    encoded .= "6nyTeIUAgOjJml2o1vyIbV3b9gD8GCg380aYUG5r/U4zd7+RlT9ZYZP1xHlXxxzo4eR9qI9kSxKW/pvHoYnLGO2dePTr0/ZH7N7zkZKBUmvTAIVaqEamMtIB"
    encoded .= "sPUrgm6SKYz5UcJJ+4Fv+wnC6WeL2z8MBorrhdNb5UjLrSpEcQJymA0BVVF68xBv+RjwkQ8A176n4oYPMA5cz7j9NsJioW1XaLxDAKVo8JEha/HMhFIY0w3G"
    encoded .= "nn3g/WeAzj6v4J4PINzt3oRde9UagzDOARCjlOCz6H+BrT96jIEY+RVnrW8uxmCgAhoYiznjkU8ZMNaRfvfnmDf2FnDhFf5n89Sk+bqHki4VRM7jBrgLHp5X"
    encoded .= "F7eqBmZ5aVi/pDb4vCLovXdlbOIcQIU/77qfgV5XprZ7JMD2tgOPdRiSl7Oq1GqBkAbBlEhdh+BrtmBmIgmlmsuvbqrVwjGajj2UNof4/CSU0F+zlVyoRGxn"
    encoded .= "JgKBYr9VzEOzJyuYl+Zi6IZQldyY4KfbgMVNJqAUpsUW8Y7dwDc9t9DpZ4vlHwarrXX8CXlDktoB6t1cRgGJEWCgMjMRMJmKlN/6ccbVb2G+8s2M6z8AHDwI"
    encoded .= "8Cjz6zIVgNg5BUarrRIGSq4wySvUbL7NTFiOwIGbGDd+BPzuf6iYbgL7Twfd43zCfR8CPu9zC3btk6nEYiFabhH8RhEs752BmIwkHjjYEfRcOkmSmjMe8+UD"
    encoded .= "5kcZl/8yY8feZExUBvzYd8BzWUyI4oUvSZ9aw9pdrUBZHkdQG+OVoSYbzX5JFEAXp1L5S9ladmx4fG3GCW2q8ZoZxSe6tncsOJfwxi0qqqOWz4jPwZVA+9RJ"
    encoded .= "8xQCh2GM8td0meWlZIWtGKTXXG35JRHZIyUUPDIIeEBBkVO/yKesuKvIbbXt1dJGgAaeGJyIiqPBKF5EPBJQmL7pxwrOvg+wmANDMfFqW8qGw7wRW2eXU71U"
    encoded .= "wImw9DA8MJ1Kpz/wz+C3vb7S+97KfOuNDB4IG5vAjh1S55jAeqxpmYmBkcKr9OHNmA3GdALMJjZUjNtuJn7baxlv+SvglDNHXPioioc8vuCu9xH1Xi6AOE8h"
    encoded .= "cZyMpW2Ew2DAz1h0qQ8QePwziG69iflVv8vYs59Qx5A7ly8zkZ4y3bYPMzr5uRUDYtrmFbdeX6sCsANMsxy5KJfOMwhOhN6IUEU6TacGmUNSVd1WGHB7x4Kj"
    encoded .= "YkBY1nY5KqLhvaXNbgnr8+yMJb9nBUypG56saF8CIP3tp6ykKKzaXWmHbe0VLWCZamWr1LXvDCbkKWl6HjmG1QBRLmOTv8UW4et+mHDvB0S0n8n8jy7Ep8pt"
    encoded .= "oJS/dKhVS1YrMJvJd1e/jfHG/wNc/U7GsjLv2JRz/yqLoo81yLTcourAq16MsimPte1cA8Qqy8lw4hERFUwGxnS3HO5y2wHG619R8XevZFz4MMLnfSXxPS4Q"
    encoded .= "7V3MRYFDclZH2JVXtUyMHzmzSWlYLoEv/06iG64t/PZ/YOzaR6ij1pCma2t0PrdmGcPd/u7OhfQdq72QGuhYQm8koax4BEirSV2n1zgDjRw5XxQInQ558E44"
    encoded .= "D+B1DX3+weWbZWkpM1c+x9tygVCQeM4GSL5vov3mNq9jEtK2Ylj5aKNLl24sKID0Wms09Tdl0nfJn5Fnu3kjJYF0NEYa9iRMw0C4/VbGl38z43MfW1z5w5oE"
    encoded .= "QUZP8x4665sNvH7FVZRpMiF88Ermv/79ive9QwBjcwfEM2GgVkr9EjNDsENms1UjN6GxVBWKmDlAJo0O3gTo7sTJVE79GZfA217HeNebGQ+6GPyEpxPd5eyC"
    encoded .= "cSRBrRIzaHfysHp5eCC6ASqyWahMCp75o4SPfdeIj9/E2JiRHguXlM4sUp47Wd9Y1tMtWUrm/YkKE4psJNRaedxLnkmCG25C1ERRlzEwx5Q6pfelZm0rzoTs"
    encoded .= "ZJiBTyW7//gLU3HRkT5El5iRDnvkQGv7Lis5YsqOKksLo64AMKLw2r1duvaZhWTVXVQFyeaY0zoubOACiGx+1gZ/MgJES4ZL/juhjZeyAv4MoxTg8EHGI59U"
    encoded .= "8MRnFCwWovy5D3cYxKEsPmaB5d44EiZTYH6U8KqXMr/4vzCu+gfGxpSxuak21ElkF5xC6cfHVMA8vw7b2y2JFdZF/04qMn7Yd7Uy6lIe2LkXKFPg7/4MeOGz"
    encoded .= "mF93BTNR4cm0oI6MkJgwJhmQDXtj00/wpBTZSLTnFOCZzyGUERg5czMspdBlchkuupxiHn5s09esz763JTyUxnDoiBYQuzeaM/56oc1XlkkET5r29Td3z0k7"
    encoded .= "d2Qy11/bAgA75t1RnuU3g1x5zR1sehiaAtt6xpBglR8s7GVbJQsTh0ZJvXwD0KnvnGMLaYjSs0k944apllmalWu1nhVCgBZIiDAUwrHDwFl3J/6q7yKxxEgW"
    encoded .= "HlgztchGJ3LFDHwtg3E2I1z9NsaLn7PkN/yRKP3uPQVLtjyJlj/Mslafo0f+WvYMNLlBtzryTwg6wkNotaBhCSECiLv2AYsl4Q9+mfErP7TER68BprOib+Ch"
    encoded .= "1sgmDM7Vh9cRQCXxgEr3ftAET/pa4MitQJlQ6kgLolIZtfQ2UTRqZM0xPQMVh5liHSV7b0BlNXcUiix2Kc1F4ZVGRqHqB/xx6mTRYkzhVhD5ONyJAIBqcZRI"
    encoded .= "8kv8YFVuCJp2QpWgKVmQ2nfMhFsL9PMkQ22XuGSNm64n4RELz2FeewUzdPaRtKCKWgNty5jc0Gs0xRA7sNh80IBvNiU87dmgHbvk5J5SjF0B38EfUqsttFUP"
    encoded .= "nGpbVdzrQoS/+p2K//WTzDd8GNi52/oADEQNX/KqSm2Rcw2YcQJn1rFgT+2OGo1lrMuGTVJr40lYi+MSoMLYdRLwvncyXvRDFW/5S+nPWmRPQ5aVU4fIZUKW"
    encoded .= "KwnjWPFFzyw4/yLGscPmZakMJIX3tfcuz4CKGSF7JrwE9RRc4PScg2RBOG2vXk1Xrwzy96Vk4U4fXcaIEtDlAtZ9uW9ljFRs49oWABCXiNV1oJrd/FboTNHd"
    encoded .= "/qQftT4A7ojsUkT6Gpcd1k4bLmtBIA8imo1MTbIg59LUfIK6wo2XgAwCvR+26tEwA6Uwjh0GvvgbCfe8SFxVy+41jPDCxkef67nlcAszjhLhP3IQeNllFX/2"
    encoded .= "ssqzKbC5qXsJKM0TkS1XdKMorSOzbLNWoDaYaaciQodvoV5B5VTS0S++9GExYFPaxiVjYycw36r47Z8Z8cpfrRgmpHN6fUBZ4DrRNUps+wbUMJB4PdMN4JLv"
    encoded .= "nWA2YbCfkkGA8saUJtdHLbqvyBxnOfSprnpnjUwxKjNVtMLZGMxu/0luMLyFcLn9m+xNpysnCGMb1/YiBrkDaMdZrKMiUipj5StIT/JR97fZLCKC7czoBIrd"
    encoded .= "5VCLnz638wFVkhoJQXnuFOf4643kWsU57bmLq4LeUt06Dz3cMwg0AEdvZ5x7IXDxl4PGUZJqXLCNBlNApRMkbz6Cd1HCu3VkzGaFb/4w8NIfHXHVW8C7TpKj"
    encoded .= "uceKFrCIfISrWvQKWdbT1TDtE3EpxIXYUiv0cVUt46OCuB3RFR5F7rMxh1qFIlM3DoNJsOU63txF/Oe/Df7dn2YGFx4GikivjdGaDUZ+K1nEUmSF4ZwLgIu/"
    encoded .= "Ajh0mwZa3ejI7wTpTZ09yGjjWGmdbZwEqSiKpsfSNILDO2qrCV7mmb/LsLtZWt5O41JXg7jZDL6ta9sAYJ2hKixpwYuaMvbbLAyrtZEyau3WzMuy2o1VNh8a"
    encoded .= "4ka+ddbs9CcnpWm8gZRIUcVKNOvLVlWyXE1f2tshlP391twBTCgTwlO+BTRMEC8gMaFIytBU4sJiGYaEscp8/4ZrgJf+WOWPXAvevRfgkWAxAuvTyECzNdwt"
    encoded .= "Fzy/YQRABezpun0/OayOWz/lFzNiF2VmBuVemCWLYQrrm5phidbv3s9406sq/tdzlxgXAA0Z6NGkl0dPhYcyF4+xpCJA9aSvGXDGWYT5Ubi7xUkWOC09mYzG"
    encoded .= "/NqWqHGHl8tUKmRLto05dv63Pjr5sz0cxZQSPrptCnA+1LaaXm4TB7YfA4i+dP8Gyc40jj9sU0d1NY6BzXPrQmDLj7Cbzbyf79i9zT03PuVABUPRM00H+qtJ"
    encoded .= "vrCxzbX2LgBcrlqaqqS+HjsEPPpLCu6lrr8spPCKsjR0O6glgK3i9t9wDfAbPz7SgQOMHbskE48IGPQ1YD2OVDZDWtq21rQtwhSeWK0c++1VEc3r8Xlxaq7h"
    encoded .= "f7beZh99qrwqo6RTm90nA299LeNlPzGijhTvANSOcfNEjHOXcENEsjqy+yTCF399weKIZeCZR5PzProx8Gw0Mq4ocqLZA2I8bnRCA3iUv0wrDuAO89uW5V8O"
    encoded .= "A9DoGnOUSnM6O6hHvtheMvD2PIAxvRgELWJmZQlnJnXNCaTkNwfyrlw64BKUQXAr5RvEfKwFgiAkBMfLkwgLqST3kX573ZNx36yeUtN0wZppYh92E4zFFmPf"
    encoded .= "KcATn0FU84sF2i4mS9Ghggl9lWW+mz5c8bL/VvngbeAdO0hdfkniIYIvw61FN0pLc1rEZmymOOMIqiOIWObhEYKQo7qHoXg//cc3iKw5TYkRSmfg1PAfPs91"
    encoded .= "b5GBvacC//R68Mv/e40TjnO93RV4wtkEUimMcQQe/oUF5z+AsHVUjYd5C2kkVt7KbMamGxfrQ3p09cfiAyrjnhWo8iNH18d4OC/do04N5HTU1hQBXg/DrMWd"
    encoded .= "eyIQ1RK1ZxzLK6fKzDR/jMETRDc+NV0xIawWJU0tFfJ11IjKS30ZBLyerAauwCGKpHNjE0sZhB7KE5E2XclNa7lmvudFJRp97DDh876C6OS7MMYlw0/tbXou"
    encoded .= "D1pabGyNVdCphDJlHL4V/Ds/yXzgJsaOnYxaRXmKmWQTsrVeBSPtq/UC0m/hyrisVMdISjp2WI4kO3IbsHWIMT9UcfQgY34srJMKnPCQkxx045EQLqy2s3d1"
    encoded .= "dWUcgd37gb99NfMrXyoHgkRefKuoPkSp88l5pjoyTaZMT/gaknXnNHEN+ci/80a2NTs9M/HaGcp/u3BT02e35p4mn/hEueLo2Yomm8FqFcgvBrY9qd/eseBc"
    encoded .= "xNAwyE4Fcn5Qa4FjoBtvHrYPwB5ypUlCaRXIBj+GnR7UeBo60Hmq0Y5l3Mh5+QAk60yfp2q6FgMTSpj6DqWlMf0JX3wk9Y28W8AZdyf8hy8lrmMl29+SBbaR"
    encoded .= "k3A6UHQvvRyLRajzwr/3M0tcfx1h9z7CuITvrCO1MlbXyLpZMTGzMoHEW/Cu1oQ14wiqLHUujknOwj3vy7jnAwmnnwPa2AS2DoE/9F7GO/+WccN1wI7d+v4B"
    encoded .= "ozuDQmYa9QOTgN1YmcbfeDBWYNdJjD/7rcp3u1ehBz6WsJhDtxdLqeB4GnOtzxSlDMByBC56NOFe9wd94Crm2c5WVlm1kQ1MjZZk7hhRxgK3uZ89DWA1NAmQ"
    encoded .= "QrigcuLV+mIiU+Iphe7Ei2yT7hvoN+K9PQTY9l6AqTfoIpw+BVOqBibEcsYatr14IV9udJuOZFe/U+CMFvaR0L6/K9XTmDyK5+IljOwD3+zUcol2WwVbemya"
    encoded .= "cRQQWocJMB4C/YenEO/czZhrzvsKs3IzmQwDt0qYzIBX/+aIq94m04lxlClRBEMbEtPwt0uktYLEYyCRsULMzGRtDRPC0UPA6WcAT/kOwvkPcfGy+uiBjwMe"
    encoded .= "/3TCG/+Q+TUvr6hEGAZdNqA17F81937T5TnfZzQrHwRgugn8/i9WPvNehU47G1guzOy2CJ234uYzBgiypDidAY//qoL3vWOkysT+Pkg38eTjnUnmVH8TuuD+"
    encoded .= "Q68BydoTudzn7b2sni7rtASFFS/DGjSpIebxWlpnJ9bA9qP629w4UGynqTdsSlpBvnyUX7jhIYlsqZnAXDT6awKvxdTKE6WULGZf+rA6u8Dpindo0fP0rV9O"
    encoded .= "iqFztuZo3VGpN1stGUxOBKSugQhYbgGn3g142JPkmeImOUhpUZvU8suoEgg8AtMZ4d1vZrz+Dyp2n0QYR4p0BgWdZnqoPzLHp+h2dhkpUy38LgOwdZRw7v0I"
    encoded .= "3/6zROc/pNJiUbFcEJYLxnJesZgztrYYm7sZX/D1hb71eRPs2sngsWoyjgyk1e046w5Tv+xGiZbV9Z+ifZhOgdtuBS7/OeblPG1NBvsyJtKzoTDsslhIYgEP"
    encoded .= "eAzh7vcmbB0JOWsvU6VEm4tHopRN/izwSN3fnTwnoHGpsVOxU0PsHYgVoJRVpP2Tv91rsmkKc9iwbVzbXAUYK3N6/x4QJ5sIkumUj7ynhSii+sb0yvIKk4pk"
    encoded .= "XU1Ign6G5WzLZg/jrBtmY0Jiji2ZhXDBWRLz/XjeorYJayQJhbs2UrLXCgAGBaACHD0KPOixhN37QIs527K+ljcJJW/P+mT2q7KcvnPwZsYf/wpzmdjD0nit"
    encoded .= "rEk8ksiz1M/McWiL12vJTIaQlkuhqyEEYJwTTrkL8HU/QrRnP2GxkBgGUZUgnZ5LOBkEuBdzwr0/Z6Cv+h7CYislpySU8RVvDsC25bcMBL3H5VhFQntlYOdu"
    encoded .= "wrvfxnjDH0B4gQhG2pkIHZ46nz2nYgRmOwgPfWLBuKWg7Py3gU60mOKbV+DKzalIIKv3K8mNjVNGBFPWqnWNuhcmAqvc1dcF2RvUUqlJxoC53okvBmGL96bE"
    encoded .= "BW2cIicTDMkkK2nlKRTbLA+SxYjOOPNGpmAk1io8YHopg5yhoylmzHclMLRNYx6jHbrWC4XV3KVBRgyOUZfA7r2Ehz8x+W5riLH4BUU1iAFllAL+s9+sfNON"
    encoded .= "jM0NC7JG2fCGwgvwjL7cVDZHAFiDrLVq9B/A4ijjiV9L2HcKsJhXDEV5kemiSLWlUjHfWuLCRxc86PMKtg4TKEU4rd52zZujrlXTC5EQ6hkCWR5kbO4m/MXv"
    encoded .= "Mm76CHgyAewgWLZ5ufMvDShFvMliMA9+AmHfyZqOnFrJRiusjH7bgJu22blergvJc7Cv3dP1Z+2+Krcn9nQ/aQhdpq2Lqm8ys0juxZ25G5BoaPoWrgiDKpOc"
    encoded .= "8UB2BBUrCtJYmWz1n5l8HT5AgVZkIixvFqjUT5UVXyHgxPisLcpZf689R+po2CQjox14iZq1yr5uDdusWxmA+RZwwcPkbL/lQqL0vgyUqqfmn1BSXe/nf/lH"
    encoded .= "xltfy9izT54YQBhAcpT4muXLmgUm/3Dak+GgLf0pJNOV0+5KuOAR0P0JlJ62rregXUpxMH3YFxc/ldfoN+u2ouccvMonRCWOgHLb2igDmEwZt98G/NX/TuOZ"
    encoded .= "FS49a9M6W5G36dpyybjLXQnnPYjp2BHdI9DiI/rmC4OLrqES24FC6munjRE+tisAHHyTyGtegnRHP3c3kcB9VfJTE9F5mAAw1+2d87mdwrppFAQVqiR12j9X"
    encoded .= "foAli8/NbHKXskebPyTB8e+qHWNtP4kcc88MsZ0vFIOhCuwKQOTzFmM/JXpaaYDfaJI31D21v8maAcBFXnAJRKJJZ+C9Vuo/MYMK8XIBvPbljGGIVRKrxDbx"
    encoded .= "FMh8mEzyqC3XyEe2OEm8SiEsF4RzHwhs7pR5MmhVcb0O5xP7UeVnngvs2wfMj4YVzGJt4+E1OZPbZa7G8LOAlDsvDNSlbHR6y18zPnQV8TBpM4Xz0AW4hghI"
    encoded .= "MFBKPPixBB7Z+4KaDYwGT9PcOyujAaoJHZlkpHRHX50yerQfFZEIZ/SJ7IS8+rSUEXGv7B7oIDv31AvyTEBOSxfHcW1zMxDsJaQhyElZMzABoSSNEiB/rk58"
    encoded .= "viIwF53MSka5FqJGlPKQCX0tilpehUGAMZfSAFN6IM1mW+VPFszwbbEFnHYm4bwHaUS8X/pLChpBQB18IjATDwPwjtcxrn0PsGOnTn904GtfD9nTKqzJElMn"
    encoded .= "iDYti/m4bgYaGfvPoKCk0aLEyTXmbblk7NwLnHw69FVd5G23/UzLtYAKuPQpB4xjkJTvdmBoImG+Bbzm91QJUsot+ZjGVbVtyyEZBoGK+z50wKlnEOZbjEj3"
    encoded .= "jafdCzHAS7DJPgDGUw7tVfBs3l2I8Ejg7cCNmctr6mR/EA4pz+BT4RZgDCRVLu68GEC1RCCOKG9j3eAI6TJNFiAlwLKi3CEIDgfaF9niai++ZGd/GA9Gblj+"
    encoded .= "CNSnVNYyzlSQ0ufI6qNG6OTh1CVfysmNxoCZUBAx5seA+z4Y2LGLqc6b0vKIDTgHzW69qkTj50eBN/4hg6axl9828bg7j/SiVG2hSZAycGgyLsk/xm5UlmOz"
    encoded .= "bLSasVRl5kxz/iBMLIUw25mzBuHWuwH9hC0CTHHGfA/S6Sl/lkj4sbETeOffMT54JXgyIY8FhHeVjIHey0fELRbAvlOA8x9AWBw1el0AYJwqso0HlUDVTFka"
    encoded .= "yKZ7iUft6k5Y98BE+ZQBMYOsJ0UlWU0R5AB0SuNPgB3WWblu75Cf7RRmzzmmVhmhg+4lrZOJYqSPHZPsFquJaq0OOYPd1ueeN1V21sRRtk1I9aQK528MEUXB"
    encoded .= "xrsxry+jbdYJZmAyEC58mDzcg1QONtpxXq6IypuhEP75DRUfvoYx2wRGFjiXOIJGK9LqQWMFXOlbnjZayMGhUAn41uR+YOx5xwNu3Xaru/rWVvaTdpDc0lzz"
    encoded .= "iox4Y9w3HzSmXaCliBfwpj+uqUQCihZ24Dsakd7FCOL7PpSaPSHeFpEmfDGKDZsygtVw9LYgprKpb8lAuDcEGx8pnH3XFYueUIX7L72tlptgbHcrwKf+clCX"
    encoded .= "NpalKH+Tr7l2RhURiq/pZ4HPSyvQZ1bXUa2pyMpuQj1an1XSSbs+EavT6Vv2J328Qg/aUFQTk+DEf3uAxP0/6VTGuRforcRZBny5tDaxg6hsmBCPC+AtfwFM"
    encoded .= "Zojx917D8/MzSLllaErr8241QmjjWRXCAsQ+25Z/KymzmU8ZaHRJMaYbFgsy/rfPN5fTqBQQpWc4Hf4ofagjsLkT+Oc3ATd9BJhM4RuWXCcbZG5jBQaQ97qo"
    encoded .= "YPceSTt2KtXCNUrZi5UxluSZzCNu8v7b5yKVPW7X5kw/TmAS9x2wOQNB8CSmIyqzVCrQHOP5Ca9tAYC/dCRxyKySEe4DmAbB4gZZuZud0SqkSJa5AQL9x114"
    encoded .= "AHkZpLcccmXvgJoybd4/r1pzjwp1IOBNcWNpCcDWMcbdzyfs2kdYLrq1AkYSjG7eq5ktpRA+8E7Gte8FZpvCi5XYzye4wpasySF3upMyuhsac2mP2SSQz8qb"
    encoded .= "yIF7eMYRTkLIUOMQbdjqjz0bMJiec94k/vQkMTBMgEO3Ae/8W4FJzzhFq+Sps96aeDsFp50NnHkPwvyY4qGCSJO4BoCY2XOm/SvR5Eq+lck6jWbzWvMTG9AS"
    encoded .= "w8IQJR0hkB6PZuJeEh/YT5Fam2Ck12NxfNe2g4D6aUUQbLDcSurOsjqCamUKSxxk9nhmdUdnyaWgEc4EItlrsIlnXixgSI5CJcVrZbAZ0GqHh1ToHnoL+3HT"
    encoded .= "XvPZgljpqiNwrweqq1mZIgjHMRdNHkNjxvX+P722YrlUITWQYGBUznku1B2hgX7nX68xt2aZfLyQyjuv02gk5Q95Dgg3hnOuXyXb/vMkLkSf2ToXDTfZnkF+"
    encoded .= "s1ALO19vGBhXvlFiGGUIwDAnlaA2ImXWQW3MclFpMiU69wLJdHRGpRNrHTtYJVwFO3IbkqnPWth+aCx+9jqtfhvXMJqpt407n9239iW9nIWCV0f9E12f0olA"
    encoded .= "BHhEeUxjYwd3VJ0SuFtoAm0Wp3MXo95VRua8bi9FFMGWZGsz/12wzXXSzyIIykwbhXRWoCX/cEKRLAyO2rldBjZ3FpxzvgxQ0W25tuZrOh6wEs/WEZhMgNsP"
    encoded .= "AO97h8z95cQd9u5xIsSfZ3NB4VbFHVIDwzU4YQDtSVEJKk00m8eyS8sNNCIPARUgv1iFM584sY+BZkdcut/QGI3CENQCsVwJ0w3Ch68GPv4h6H4Ee0T+y4ln"
    encoded .= "2ejKbwZQcPZ90o4o6w87Lra8ZrDnrzCj1hpylRhlcazOfW2U3ujMX1QNnjAD9kYB4UvmuD2biAYrJhqQizC/Dsd3bTMVOD9IbQdNOfRzRvPeYjn6c2ekiBv3"
    encoded .= "rQ/o5OfXyHa4V+p+ylOEMMHWjA5tWkbyA1yDwqQfa1sDICsWdSHv9zvtbH0ij5mRkhXJvvRBI3zw3RW3HpB9/3YmQTgKUa0BkCdWeX3hMlJqKbv4bRowJ93q"
    encoded .= "+0ftbx8L8ngCIx0T71O/wNb8vDeRgLhpRv/oxzWf3Yf8myWV98gh4H3v0GeZE+NTiJUVGHPlxAAq7nbPgs1N9QozFhqpNkz2j1l/RoqvdDSnge89KduB2l4G"
    encoded .= "M2Eo4MlY+q+v5mQaE6pCXzhFAPfHOX6Sa5uZgOZtpA0nID8UInWlSa4xD6WUhKwUQiZCEz30JaUkmLESEgk2PfomvWosUXPlk4FZGdAz1chzL8CtQHuxrFWP"
    encoded .= "S+C0uwK79wLjsvojrdJHm52UAwD+5a3iMVnuupxZEGvUbcore9yOU72t+5+sYKI9PKpMS29luPutgutgKIFd91IqKS8CKJopGwEDiAcQl2bUEi1acBWLKPHR"
    encoded .= "PggtVIBr3qUqrrkZNvYrpoPgWmtZoSefQdh9si2FxgpQ4400EJs2qCGNE6dxSGQbcJLxIwN5VBG67e1n5XfivVfcyGKGHPhs7LE4vmtbaYPQYL9s9XWNjH5z"
    encoded .= "ctOMI4nQOuYYKTuihCiH1bIHS4Ef0yw7kRJANIgYQ94uFyosmUAO8AxGHVTEMBdnvkXxq7pzTqXveTWzIZHk0+8hKFGrve6qM3AZtPR5BjAM4Pkx4IPvBiYb"
    encoded .= "uScpwGmI5+zMwbmczGTWToCplAJbmsvIVog0Pbgxi0lJuss6EmSsHIRi8i0BsAwoQpcDLQPNmfJJhiLpSsfExgJISikfKgPDlPHB9wCHbyfs2kMYlxGXiBHT"
    encoded .= "h5OcEGTM9u4nnHIa4dZbGZMZN6zwj2sAsjDkNY82CNQqpDUZzbPz1861ID3nAra8m4YipaYIoJEtGVrQHZD8oy4eIdQBOP4pwPbOA6gjDzRV4esi8G4p26yp"
    encoded .= "RglCAlr97eY5kmYqmVpH53DrIokrq3S5QNpcEcrcGswnUs01hK8cn5NLaqfHyhFeFRs7CNNpRLEjVVZTiNVynHbXDEAdcdrFwH6/yaVU3HQ94Zab5Fx8Tkxb"
    encoded .= "o4rdRWDdcUYAhkFeMLpYAostiqOnM5gQ6044SY09fLtsjImxWW2fkL6HD7Uv7m4dBo4cVLVj04Y0xkQgMHFlUJEzDiaTBp+dzuYVc0RpWc4GKxSsTIADNwI3"
    encoded .= "fRjYdT+9V9RQkNTnewa8Tva+T6eE/acRrr5K5MuWLhnaN/OnE5FGnr2FnAgSZIa89lmaNuOWmm0sgMBiDkNljlvwOzy40KkAw9XJhKoW9bc/0bUtACAeTPfl"
    encoded .= "byPDkiey9MJ2d8U8I+ZVKYjnaKfMK7KkVlBwyunA/tMZm7tFsC3IVFxRg2WliOUtVHT7qlkl2aRjzw4DoUyYCIXtIAvrSxnM2yDMjzI+8n7GNe+uuO1AwWyH"
    encoded .= "InNlz5yRWAdjMgWdckbwvXFjU/296TRefOyDjGNHCJt7YpXCPRcAOcpebC1GcxVqDXt7+23yYtBTTiuYbjDGkd0qW6QZYKICDIMI0N5TGLv2GY2mAWz6J5bG"
    encoded .= "HTPyeSy7+DPucQF4mBF27BFCzAtgyFGkdnrRuCTcfpBx202MWz5OKANhY5OwVKDKB7Q0aclppP2TTClx9DDjhmuI73E/XXcJYys8os4h8UqkUyedxrovoIU5"
    encoded .= "82VD8ewILC0bugmFmi7YyPGZzPAEwJKR0AlLHKoRRsN5QkFj0OmPko41AcBjAbwen/za3pFgkbYe8RxoZ3UFIObf4Yw1WmBTh2Rx7OiryQS4/RbgzLsTvvDr"
    encoded .= "gPs+tMibbqyNFtx6c6q3CtC+b6gbep9Jxyii8GrRAmDArTcx3vzKilf9FmNe5ZXabOaPJYo/TIG9+40qy9iTeXojkFmI08h96F9GOR8faR1dBTSf8UjmdDJA"
    encoded .= "VVKuieQtuIujwP0eSHjEk4FzLgQ2dxns2oKybSyK6VkpBNCgB2bUJnnJYulMYYHd5XQFE1f6q783s9tEc50hYiyXwOGDwPvfzvjr361475WM3SeTHobinXcA"
    encoded .= "au2mV+OyxwzceJ3cNAPiLbvXxegjcsbLU88gSbBSOQwdTcuPacugr0t1Yk1ZefX7RgjV+NmzrvyN5CXQ0KuiuufonkV+iMPQCanLO+HtwHr5PI7MzbPeIXSK"
    encoded .= "LZKfM/DYXZp0J3VCts0ujhVc/OWEL/1GwsbOEeMIjMuSXKnqepSEghyRwOLqc7N2/ElcIsdiEBGzTvIJkiV30qmEL/x6wj0vAn7j/2McPUIYpuxJLXVkbOwE"
    encoded .= "7z5JrStlW9LKXTZFZFgF4MZrGeSn30ZyRysc8E7zaKCpmXEbhKd+N+FBTyAAo+4hIBQQpUQ6CSrKGiMsP2EgPWVI++MvtiXWl+jKWPNadsrN5VKcdRnjSsLH"
    encoded .= "NufAXGMiYN9+woMfT7j/owr+4JeAN76SsWMPy5uCUxucaXezaSAkf1MBbvqwEOyh8MQ4y5H3UJnPu6XA3v2EYYiBCosu3hZnj22NJ+Gy7obbxjclZCVgMWBr"
    encoded .= "MMmmrg4aHIzTv7P1dzo7VJQ/txcD2OZmIHF+S8+GDK5kCZLSCQvr5Gy8mONAB5Fw2wHgcx8HfPV3kbwual7AFQRUolKJClMpkgteihDhbn+JKQAVgAZ19Yv+"
    encoded .= "DDINaH70lJsyiIsqz1YqA1EZQDSAAKbFotLWMdB5Dx7oO583YHNT4hCW516ZsGNPweauSAwwQTHLIH0GYopEMNd6Ma+4/RY5Ww+MJEjBV6u4VtBYQSOYRmYa"
    encoded .= "R2BjA/iP/4XwoCcAiwXTYl40AYtprDInryyxAl6yn1FvLvaYz/7vjLcpP1gOKhXS2c2ZQ53oFFEB2Vlecra4JEIUAhVi3RdDtFwwbW1VGqbA036w4AufAXmH"
    encoded .= "XwqySx5+vyagbab95EMBbv04UEdpqJFMJd+MbVY6W63Y3GlWuTNKMMPF9ubkWNhgjrMLoZvfOLwjd/cRlp9DCNoAqOlC8nyyc0vpLxehFX+y/+P4r08pEzCs"
    encoded .= "OLvQNn3K0otA8gxaNjejQlhsAWfdnfCl3yyHUiyXTJMJUSFqWZCDdV550iurOA+GFlhhugszBSQH8dqOAMh0VrCYA2efT3jsUwiHbkFjpXfsJExmcnJNM1id"
    encoded .= "PFo7Bo/DABy7nXDsaEEZYvdfDHA70M58BY8jtwGf/7XAuRcNWMyJDMj0oAAp3KSghnUyPaLEXnBn5TRgxuFgBSE2fg7wgR3s46uWzds0q02YTAqYicYR9CXf"
    encoded .= "MuCe58nbk0uBxDm0oeJsyOOi5Ops7ujtshNzGHoVCkGJLlrVMoI79whZtSJLmvZbCOYQffdiSF+0UpnTG8tCEHPcIdjGSXBMHxgJemCbl7IcwcuhQZSmWZeV"
    encoded .= "O/E8ANhZCKzRFds0ozR5xie4PbXEtTQ+hkPDWM6BJzy9YNfeiuWi6pJuDQH1TqJBEc7bfNvtdlGwE/DVCUE7AAECrTJTkZTWhzyJsPdkAo9qtSGxiyEdf9bm"
    encoded .= "jptAhkTkETp6mHDsKDck28nDDmSMpt9EjK1jwDn3JTz0SUTjcqRhUH5ygsyGeZwSkizjDDF4MRwrPCL7x+eZYYE5iG5YLngalWVsNee4FLXxhfH5X1uASrr1"
    encoded .= "mf1ZCTySnMpjPNF2ZRrEWM4Jy3kzpKucdsvsI8IAY2OHjF9NO4bIXl4BwVrrRRU/ABVE1fcMOvvYaiXTCz94JjYZ+UlI7CxMVj2BB1ogCJ7aDYpHSKWYgeqn"
    encoded .= "9Bzf9SmlAmdj4OiTEUlJZxNmzqmZaDo1LoC9pxLu97ABwEDDUEIg86UWK3e6x+wgsHt+BS0z4jrbZQLf1GkBHyk/Lhmn3pVx/oNl7l00BbUUEUSXd2+sN69x"
    encoded .= "x5YnF3PGuNDBs5Nik1Q1LHArSpjPgQc+njDb0OfMt7dHE1tWHctgX26ltzyrcKV3moM6zMTKSpB5FNQyXMuYzWtbqZVxzwcCJ9+FMd8CUEBGS4P/PU9UWRdb"
    encoded .= "wHKeEbItluW1EDzgB0ACnwXuFfU9bpuzF4FqKdFyH9rWVq0wQsc/ZW9mhUaAvds61x3YGoQGRk35ycfQg5e8PZ3e9nkA3kP7SR1c3aTCvqsphE2J1w4tl8Bp"
    encoded .= "dyM66SRQHdv0yfZK0ddmnNPKAyN7WPnR+L1GOJxWRJgy7lg3DekGnHmuKZk+YwKUGuRWdFVCLD4S3y0XwHJJyMkiQDcwCeXNekxmhLveC/6ML2lSWl+GqVvb"
    encoded .= "acdO5HItN9ZdDfCDfFda9jy4L7hyg5C9BoLM33fuYZx5D1kqpCJW1spUyKu2TdDdNmrd4xIYaxrktlNhM5ISNRidS1kw0LnXVmcLlCSvVGihLCfHNRaS3E4q"
    encoded .= "If6kpRSD4atGeWt1JpKRTt2yaW0n8Iw6YBvXtj2ArB5d72GC4AxI23ttDdEshLG2MmH3HgJKxcquQr+iXv8TCYOgb9Oh4G0WVHi5zuTlPpmnZsssGZ21b/Z6"
    encoded .= "n1KA5ZL9eHSZssiSnE2BQlziqmZ1KACjjnIsV8gfdaaEnQTbbDWOwOYuOcXXTgn03AH2niKkLlHCza8UFEvMdM61iLk6M83cRTMga6GEU+Zn4pOtWpx8utlH"
    encoded .= "asY3AqOioE3djRXViGXCgrC4Cuhtee1/QH20ye0WdkcCQ5XM1+BLtVqa6B8cdciXh3Uq48QkQ5royziSN7WxMybRpexcx/o7urZ/HoAJFbU5zTGJ7TtCztro"
    encoded .= "TDCPiLDYAqOyLlGFZcidYx3YbGmd9ZQGSMloqbCVQs5Gtr06K2uUW/1+DiAqDnxMPBfPSjTXPLHBhNzlhiyMrOBiB6yrUJRib8LNVofd9csVFwKGtDRnS3qW"
    encoded .= "Mp2DoEpViFI206zfuGVKzEgKmnmZPzfLuq0eJNa34hx7PsKa2ZCOo3VTdpSOsDeaGVdWpUtSr+VtTBl5stL739502iHYHSZir9kltDBkoJDhxAe5OzCg32+R"
    encoded .= "Y0wCYhnCkhwkyHVxpjw4lKjRpy22AAlW9Pj4ya5tAUB+u5W7S6nFPI+yTgWlQBwpZVaNMAyMj32YcfC2Cj113Ou1TRRiZQ00pEyxuZczObUTC6zajklaU9bG"
    encoded .= "tLmRvRQCqdVWF70wFnPg2vfKSTTEsixpu+u4IaSxjY310IFlgDHMGNON6ItiTFg8dTgtXsaQFNhjRwg3fTRQz8umX0FOdNCEiiyOy7yS/i9gqwLHtn9qVehC"
    encoded .= "n7rYQQLggAzrS4yxpelSARZz4PprABrIX1gSz0d0IqmftzXZlPHIyJ9C82s9F7Mx46inAiX7Zf0aNMAvbrpygS0O0G4NAnE+tyM8OcqfFYiTLITKZ2DIYMcN"
    encoded .= "v61HSWyh5++bZqz09RNdn1IQMFGHLBj5u5UgkFk9n+uKMAwTxg0fYrz/nzWqTkUWlCnQzoVBQSS3Y0bPjXBnxc3LyAMMf4Qad9wvNRe2LZdZ3u47mRBf+27C"
    encoded .= "DdcxduwU4S1EmB/VfHryR6USyk50gF4IKmFzh6zls+5baCaWxi5IwlHef751jPGef5A6qBRXJpgl6IfHvoMpuJPghduR1PhG8iKM6cEvU+amiVb4k6ayo6tZ"
    encoded .= "PQGuyQS47r2Ma94jp/3UBsRbhOauP2DC5g7CZMYYa5uLkcHdytpnU5Zxbicvm0VIlrYzLokDqPlcHuammYQCjRWUdww4DPtqQdMxHxRnm3c4g57R5yneXEw9"
    encoded .= "7rwpQATz2+BIcD1EqBSxWiX2TFk/5Jlk8agAb/wTQF5/kaQpBwI4RZhBK8G+PBcLHnZo2zoo4HBJ3M40HSLZjAIGl6EwQPiz/12xHBFpswQcup2xnDOGEiLS"
    encoded .= "dFZvma12bgLYuUfy4ase8xtnwUcVvqSqv+oIzDYZ73wT4/YDRd+UkwSEyDe22BIpG9NXLlr5ZFxctZtBegMKLKX9XX0W61BF7mMJ5lmIpzAwQPjrlwPzuSYD"
    encoded .= "+dzGrX/K7kjfkyjvrj2S0BOeg2ZyJleIFPTSowyMOHJI+JmyfECqqI1O5pHTQRqrHy3h4N0AgfMrgQmrrKayjDhDpGVrt0Rt7LUP6Z7JE6N74JNc20sEGjGG"
    encoded .= "YHKixkuY4Vs97F+/bqOsAFfCzj3A1Vcx/80fVbEAVXLTYcJABCZ/J0u0D2UmJQdR8xPCFLN/zhF4NoKMHo6BthviWZHvU/jT36h45z9I4o+f2QbGsUOMrSN+"
    encoded .= "eps+voribaYqYRxBG7tAO3bJEiOpR2NCkgM9BNlTb0o2mwEHbwVe/du2X9neeCt/tkq8mkvDPYL6F9orXhU8+c0w3zdBh0sCkazdM4fBXbFygHpVFZNpxdte"
    encoded .= "w3jr3wC79ul0rwPiCokF2C1K/45Lxt5TFd5qPCSeVEulymbDokMHGSPncWGYEfWz/TITAobCoHBwYN10ypS4gmnsxcyVSMu0bGqk1fsFE3NpkNJBOtxS/Emv"
    encoded .= "bQHAEiPlqKi7rI5seqWjvZ0nzvg2+mncmG0Cf/BS5r+8vGIyqZjOWM7rq+QvEWX9GUddH03f1Spgoi9kZGZiriSKAfm+6um11eqzewyASjqbTUZ+MmFMZyLt"
    encoded .= "/+dFFX/8G4yduwCqulWkSu+2jgKHbrf+miT1ANiOiyn6ZELYdyqTTCFKlGy8H6tCzquHAtPmTuBv/5Tx6pcxhikwmTCPI3MdGZ5MW3M/lQ+jeAxV+ZWPxxby"
    encoded .= "OXuujffmtp8DJGRlgjGO4HGEejFFfirpSof8GD3TKTDbAL/plRUv+1lgY6ekc7cbolo2UkcRQ1YQTrlb4Jvn/jv2ZxDQz34fOHgTtP9s8RDuwdFrMA+UDOha"
    encoded .= "3liCkj/UA0LjCLXRutzVXnoMBLIe5epsRPTfO28zECCvprPBcdBUctLRxb6nZJ0lBGIA3HrrQu/lv1T53f9Y8EVfC5x7YZEjsjscHnw4goIhHNhO84hkt59F"
    encoded .= "elaqS5/zEmrFLR9n+pe3jHjtKxjXvFc8Fd9opP2jQlgeI9x+MwH3AWyZK2f+2VKTOabiiqrigXDGuYXf/kaxcXbCbXZebHpPzJqNpt+NwMYm5KWZ11c87qsr"
    encoded .= "7nZvAJhw7IrsbT91HwqAiuXS8gVohYXuTbjAk/4vQjyZWp1+8sgnskIMAB+9hvDXr2C8/g9lOjOdFQUekZyK2IZjU4kmo4FFcWkgnHXPMKoFSemTNjCT5XLY"
    encoded .= "NlsGCAdujLdUNyFqtjFOboPxoblncZtA0LzaZN6cvWOASTMKHSeiT9E65V5k+6+ttwa0DT5v79oeANDg0zwnNLlOjlzqUvmrmTjdt6pIraUy2QIpe04Crnor"
    encoded .= "4/1XMu5+74rT70GYbshg5fPSq/7BVTyCqgDia702J2ZiOVcXPr8GqxW06lSY7ODzOjKOHgFu/ij45hvkVd079jKq7lZzQYKcU8AMHPiYqijLfntaMyZVLau7"
    encoded .= "uaqbd72XbEqqXFVQhahYMpJ265rVPCJgYwfwD3/BeMcbgAd+HuFeD6jYc1LVuBujDOTeDxEgr9hmXs6B+dZIZ9+n4LS7EkbWTT/p8taNHm9cFpwnk4K3/vVI"
    encoded .= "N14PrjpTHyZg6Q9QRzl7AZAt34duq7juX4APvAuYz4Fd+yQRqI4VQ4k89gLiqgcQWlo0kooS7JXfwJn3DJlqVIbhM2PJTE1BX+3nx69noNjruiW6RGremBjF"
    encoded .= "xEghCCQrUNlKm7VjFbd2xcJHypY97UCHxnim2nBHl5ey2FQen2hwW9f2tgPbMqj5Ir0X4NZLyBKsCnTO9MnUnmNw2V49CuzZB4AJH7waeN+VrMpMZiHCqDGJ"
    encoded .= "rajWUmKsgQ8ltO6UB2RHjskfbpW1nekM2HOSzEvHUYfVp7smTPLXxz8C5OFwVI7x94CcCYyRdea9CLv3EbYWtqpB6VHLK0+SkWSEIZ7Arn0yLXrb64C3vkZ2"
    encoded .= "kTsPBvjLO0CyjDgQY7EF3PRR5m/8r6AnPWOCcb4E21IWNfa2cyQo8Rj4y98B3vEmxo49MpR6zIABMYOqHsoiSUylADt3Ajt3afAThEJg5hpK3Agzxz03fUL/"
    encoded .= "3e5JOPUsiRsRyT4ChUvriIqKWU8xDsMAzI8xbvwoY5hQGiu3sZ2cW6IZMSOCf+aQNXrLLDDitEdVDeNUZtuS8amHAud+Z1y0hbUh3k92bXMKkI6fITQM9qgK"
    encoded .= "kVs5pGLOAKXY3CNXWBcwQh0JhRizqcwVlf3Ip9OENaBmoForUdRKKjCsAQBfIWTAzwTkGKc6tmot9VPCFPl8w7UMoIBKJA81Ud3MMwXJQoTlEjj1LMbZ5xLe"
    encoded .= "805gYxfAvquQbT27kQUHL/E4xKposHJzB2KKVoTWatMStaaVAVRgtgHMjxUMU2LNKIx2mHQCkYDcwV3BS89Pm82AXScRdu+lxE9LniHZuq3jYu8DJBKPQ/hY"
    encoded .= "zVRLbAdeJmKzKarILCAybgH3+RxgtiF7Koq309hFZzorsDPARbcR33oDeGMagkzuaKqVdaYQC5QxFTnvYEXzbWg9eJsC3hZYyLEJVyHEeGfKzVOwEXBD4q3F"
    encoded .= "M74ebmuax3ltzwMopWqkOt4MzqHAmXgBAUXfBuNMieKOdychZPOO+Rw07Kzf+j/gCsj5y2yJCS53HnAylAelKZ0xPoarmf+NYkFu+DBw9BCwY7dEplfgOym+"
    encoded .= "k8zwOMB5DyVc9U8RQiw6Uahqu3I/xRrJvQKg6jQk4gqwgJY7tAAxE+QV9VXPPCwyf59MVEEQ3kk0ZzDbLkjFFAZYLoQue82Wb8tXvjUv/GiMh/hdNnWzdhoe"
    encoded .= "J6FqViaq0H7fh7nQxCk7yu8GuNn6aMUJN3644shhYHN3FrFknZIjwmnkalpKomalIXgX7bRXIFpwNSs0pfsGWM1r0I1XRCGa2YvQV4Md77W9PABNNiIyly0J"
    encoded .= "HjrldEZQKLJ3TruTTU6DpmbC0CSVID3XmisdX122KQQmFF+wifoSs1PCR5uxaMIUdPp73bxdrU/7P0wYt9wEfOw69WPSgKWKG4EKCRWWnv8Qws5djLrM/WQU"
    encoded .= "In9HiVlxq5vzxIDC88nVi2cWQQvdMuGZhWUCTaOF9ynz14O5roWdpUMJ/jTnNIrltx9fv3SvAlwYaTN95AtkgSawbbFtdGqxBZxyFuPci9TtLwmUsvLrAMdp"
    encoded .= "xcoSMK55D2M+ag4VN9yTzyRZf1UTEWJAg0ns/OH0OUplAxfKnetJz/tdAyzo26BzjkGAvzuHFONDd+p5AKWo98gRmDWXuSYGcGtVk2mHUmk9lT993LgZwOh0"
    encoded .= "zj6La2XWo01VXeOLNAJCgTmzVpDd3Y9R4sa6m1IZSPgApVFliODPjzGuu1oIyO+qy8CnPdHf0tdSCMsl44x7gO55X8LWMamvRmIHMpFCS6TWeO4L24GhoToZ"
    encoded .= "geKj0MgEokLxkhAb057JZJbHxsbiE1ayokzauEscU97VpmBeiNly7qNkBuqmz1EQoomFgK2jwEWPIezaCxrn8Gle31/Hl+Q9FD3H4ep3VAGnXjRDuKmzDg0Y"
    encoded .= "OtBlBVU6w5frrxQs9ztGg+yByFmhnAuz8b7bgtQ0s70pwKeeCtx1xAOrjJhHc5T1X5QGK1n9nikr2pYgXcQ1P8vNc0mU3MU3hFXbH+eVcCi4AE0mgNtK7aI1"
    encoded .= "9BLwvnfp7DEhcw8cpAVCnbWLhfA5jytgTyluhjg34417H9mMbChQ9hQiqKXjAvYA5jiyB+Lcw1gzED0AM+ursVDCsq5QGzwmsDkC3NfH0EQfojxlaTrYgOkI"
    encoded .= "bG4CD/tCzZtIcrHKL7Ok8fcwALfeBFx7NTDdAMZaqae+H19LtS4Z69BZZ1f+aD3jVwZzVprMWDjfmVKpVab6YSwwPQs4JgDjnbkbsHIlRyTZu5yd04TXFPqN"
    encoded .= "6L5FwX0gbV6W75kdSoJoyX0OKukno7BfBMipdP0WolCguN9xONOWpKDxFroyzMB0Ju/2O3wbeDpdb42IEAE555sEr2oF7vdowmlnA4tjQkhl9dgZsqQfLlGy"
    encoded .= "Dvoee+VRITk9pwA8MHPpZgbmghfZ+axJQuqVEDXcaJTAlDL3B0BsR07joyBvCXYExoDIuybtQA8bFSAJtEFfyqu+jvSTiIGBgK1DhPs9jHD385mWS3Ypbrju"
    encoded .= "acQqe3p7HEU/rn1Pxa03MaYzAtYkPhAkyOrsY81RIJ1ipliJr/Frs+S9lpZ93o60lJr6HXrce23Za20VgnNgIA3Wdi36dg8E4VptXuJUJnQOUn2+TOLmhmfN"
    encoded .= "Liie0GBS41VwywzlkMhgaP5qAkREnpO8Nt+3v9d8Y4PhHYEL07oqbLfiZAoc+BhwzVUMkd91rZhHENMP638dGTt3gx7xRYT5EY7jsjqNbOhj6NyYu+AS58Yg"
    encoded .= "4BvK67Bo817/nV17rx9oVesTcc+9OnO942mBY9sApMoOjtmAP065gzLuYRFYzv573NOL4Yirr0hRNOw9NuWCQQHzP/+tLklKLUlAwzRQkjOOwTI6XAtYtT2/"
    encoded .= "hMTNYiMHwce858UhyoPmzQAgksqyQLfl18na8Vzb8wDG0S1BrTn3ScnlCIoABgJBnrMvu/VegXgCSM+SHm4Zz3DIGNjHbRVT7W9lNskSmecQkD2nrM2Kxfak"
    encoded .= "BS45eXJrNNIEhSQK/p63Wl+J3cqvEhYAp764rGEDD/sCwulnAfMtqdOPhIIJL+Dp1LB4x/r+A0AlJiY9w45ABNL8C44NQ3aeoPc5LXW6yxQCm3wjabKi3fqx"
    encoded .= "pst+YL/ojkhFuzkieUrKE6ii2IpHIRw5CFzwSML5D5FDWUrK13fpYf9HWW18A2Yz4iO3A+/4uxGzDWg693oJsh3A1HwlnhiBG9lr201yQtZ+H/F396ivwD+H"
    encoded .= "yof/EPv/Q75NLlVE77wjwYgHdUftb6QPsf7ddCVFeVeg6g4tdGT92Vy1pLdWCMiQjUViVRvko7idSbADqx2eiSPDKecZWIcy4BgYNcOsXsB0E7jqHxnHDgPD"
    encoded .= "oG5A6vpqX2N7EhEwLip27SM8+ssJ88OC/gJMlJ7IVZj+EY0AVWaqWrjq386T6E4YMZOf2pt9yfl299vFNgGjDQzkSLOgMLM8UcysqcycdDoTFc+H9RYAs9gs"
    encoded .= "VWAyY3zBN4rp44YZXR0uFxk45ca738q44SOSP2CiUxswYpdtYoAqcVEnQA/3JFN/9+ZW6Ei0NFxpWW1y7DAYIwZNc3P+xSy0pr41eAf6VN71cbwXyRQsBKj7"
    encoded .= "vp9Rc3pynXXSY+PRiIxbYvJ32xFIX/cVqBmo3NacdB2tWMIHuyndgVATC+fV4k4Ao3E9bRrwkWuBd79FLJPt/bf9+dzX0zFlKIRxZHrkkwecex5h6xBnUuAM"
    encoded .= "Mq7l9VETJhRfGeCujQa2SNzfUphuubEtw2Df7Z7f8svJr2cWV/zQrcAtNzMmswQohi76y5b9BI8MTGxsGs50fCffdFQK48htwOd9BeHcCwmLhb4fIj/EBqlG"
    encoded .= "ZgsK1uI/vqbCpiMZEG3lxad81NYtqmc7xJuqnXMG6G37q3/nGA44josLnoS42nmRrl/dZiV7nhmoVO88D6DqoeOB66tI4J2nla/Cqjfcy0OmzzDbrj50MO9L"
    encoded .= "YO6Ou0yyi70TSFFfTCvte4P0RLSRpPTL4+wD0HZSGmFGk+hSK/APfyblS1nlgTxOphkNXxhS12wT+OJvLsDYgqJ5PpxBwISbjK/Rf5vDWhc1gy3RAGxsEq55"
    encoded .= "J2OxFe/wM1PkAShGiukoTerzf+i9jJtvkO3JjYA3oyoiXQtTO6fNCkOJZuG5b7ElwvwI4bR7AF/0TfIqNEr9zONCrF6cCqAel8YA8WQKfOw64J1vZuzY2Utf"
    encoded .= "K8SJS00vzFmK/f8hQLlsa4hsnDLNxmtuPrrcupynUVYwZISHwkm+uQIY78RVAKJKxtziJ+EmvMtLOwGayWU2ZGsHj/sHrBSnDsJVLmFsKq5KlafpfawheK+K"
    encoded .= "YU26cFt3Yq5lVedVMNvfHDEL9vY2dzHe9VbGh98r+eZu9dbR1dCmTmUBlgum8x9W8HlfVnD0oLzJKF+6o6zhqQNKBhPrm3aimtMFBuuKznST+Lr3Md7xRsuJ"
    encoded .= "L/p25mBtPqTDLKfo/4jXXlFREdZ4ALgw+XKfkEYYXQeSZcgMRjtWcMCTBxdbwFd+D9Huk0CjHRSYrbQDtyqjYawe9S7z+QF/+6qKWw5Y8pPsFUmzmcauBFXm"
    encoded .= "Txp0td8GkHAiv5smpq62h4ekPhB85SSuoCBapsYJEHtmDLgTE4FYE92LZRu6lQxUzAJoVpZNYp1QZV7nyXilnDptumP/pPkwohQ6Nrfxujy6Abgt3iDf7J4l"
    encoded .= "oIWgNeX08zAQjh4B3vjq1E9VTtvs1HgdLkvU/Fkr4wu/mXD2PRlbhwUYXCk0X95Prc3EWKIOJUBmG5vML7nqyGBifuVvgA/eXDCZkr+jz3iuiuRsHJfAxkbB"
    encoded .= "372S8NbXAzt365t1ssucaaBot18lV/UMTfE1X3X9iXHoZsITnkF44MWQnP/MO2uOwlgY7dZSlTc449BtI9746orZDjsTwUUtxLFRLHaFXeXcuitCZGGsgsQQ"
    encoded .= "yWQQOoXPqwNWn+U5ZA/MZMH5GER/cjKjh7S9ZUPC0sS6UJeIpx1yPTULyjlnuGveOuHKpv9YBJjaDRPOxEZebBa5CnxR7erqa0O6KVWGVWO6AZaRH2jU9UUU"
    encoded .= "ZRwZmzsZb31txYEbGJNpfmXQ+rbtricnFWBcMu3YRbjk2QUFFePCMcJBNytoWKEQmN4CyfEoxIwSrmwFpjPCjR9lvPSykQ/ezJhOtY0aB3mMo7zApBTm6Qx4"
    encoded .= "199WXP4ixo69im86UNXXGiK4CT+5JkaTkjCn2VAzuEMBjtwKnP+5wFO+HTQuJeXXccxdBDLsaz219DZlgPH3f8648cN6BiPL9utaZbpJkOPrQk7Yf1udlpYb"
    encoded .= "Yyg+QQGhyDIL93IGJGufBsNxkZvxaTwH7YMPepi+7kc7Lv3czgxAT5g6/mv0eY+6qxlAEYpiShNWzS4mc1+60fJKwnpA14zbCtYpX9uKGZHgHXlzPj8kpKFM"
    encoded .= "67yehhkjFTvbQvgi9dQgUdGfxWW/5SbiN/yJPlbDohmlMcAt/hnNZSAs5kznXFTw1d9dsHWofX13ANHq1RgBq88iBMywlQIzuLUCO3YBV1/JeOH3yRo5syQ3"
    encoded .= "zTYKzzYKT2fE0w3ig7cAr3hRxYv+S8VyCUzsrcYO3AXMTHZwSZDY2rnW06O4p8A2FGB+hHDqGUTfcBnRbDOAgvqqHEGokQXWNdRhIBw+CPzFFRWzTcDGozP3"
    encoded .= "Mj4UPzZVlSpNWshH3EkwU5gAIiYMbSgyj1gDVtmEsf3q7oXVE8PqfGzYul4o7uDa1pIBVXlnrq5O6a4oG8gQa8fBmIj51M9LERKz+uKkzAwL0VzNCOj6airj"
    encoded .= "SzjdODtYNS5dcMwBgRNAmAvctS9R8gRwSau5yhuO3/BKxmOeTDjlzPVHT1tdfpujTcldkDcHPfJLB9x4PfDn/5ux5xTCuOzoWRFKbuqOe7ymv1KmjoSdO4Eb"
    encoded .= "bwBechnz3e8NnP8gxhnnyqlDt90MfPj9hHe9Gbjhg8CuvdKJymy7glPH1EDk6SBSY2lsI4dOGF4rMBmAcQ7a3AS+5acI+8+Eb/dtKlo5dYUbrSKSuf9QgL+6"
    encoded .= "ouK6axj7TiYsF9FzW8xzcrKWprqZ81KhegawXAxRc1bBkVOhqLXaPnUl92zbPRBtudCpsItemiFgG7YngHFb6r9NALC9Z+ZpCDHcbMNsAxRZ45GUqjH2ad4W"
    encoded .= "nY/lobz5hL2XXq0/y7CpQ6QeSClLv22tUb+ObGhPPrDkVjs2d2Q0z0MYAyT1lgE4cBPjVb9V8cz/PGHw6OvfK2NEaADMl8p0Pr9cMr7s26a49WNzvPkvK/ac"
    encoded .= "UsCav99bCErA2ltdTTbyh4o9pqPKTJhtSCUffC9w9Tvg786rS9l1t7kD2LefPH24Td02t9/WIygfvqMgt067yPk/DMByQZgA+OafJNzjQsJyLm89NpBsGJeU"
    encoded .= "l1xWVDErMJ0SPn4949W/V7G5k2SrNmwPkEwgNUTliygFOQIMl8cMZ600IEIXnG1+S6cEhFfHJstl5k4YhsyrDtQTsEgNd2IQkDTCWPX89XB9lByPFOtJO2EQ"
    encoded .= "VpAqFNhrj24xUqQ0rasa/CSrboGEHKSiXNaKGqMMQns2caA/p78jKMP+ywEv00e5Kjkkc8cu4I2vYlz99pGGCfne/xhE84wsWCYEJNxHUQJqHfG1PzzgQY8m"
    encoded .= "HL6lYphmHiR+ZTBNcmwn0jJiHOzhgDf23YGbm4y9JwO79sjpPbv2Anv3ySGmdrRY/05EG5Zidbao6zwVT5vYdr0ZX8sALLfkBMdv+knCfR8hlp8GDsXKxsUa"
    encoded .= "TUFD8pvR9CtePOK2W+RwGWaCHVUv28bDmHj4gcOjystthrKrrrmeYdjJFDUfyMvLTJORVwPaRznkz+eyjdrDYN7iax47qF1Vn+Ta9stBCXAGynvO4INj784j"
    encoded .= "Sd1r6PaAn5RwBmd7hfjaQaJRXicEMWLokomoqwgCzWaZkX5I65AB0UZt33iOEwSxTm3alAVf1lyTRDQy8IqXVCzmUm/V+UROEgK1fTMYsK4UkinEZEb4xssG"
    encoded .= "PPDRwO03i2sLhm9tDFxLSJuULutM06Yn52TySebKihgEqOLHslnRkRQ54MR/nwF7CIe8rH2yDuqcfyBsHQZmU8K3/0zBhY9Wt3/InpqrJRobTI7WMf6VMJsV"
    encoded .= "vOMNFW94NWPPXj1+LB3H5qxXxlmGj72SzAWR1d1m8hOUPUQkwQJQDe4bb60Mp39yQDwAu1VwMAUH/dkWJBrA8hsAo6aKPvn1KW0H7hGrdULkM9fY3tAoHgJD"
    encoded .= "TVito40tce0yNO9ddgCUQaZD1CT4xiBvSYXaFK3tSKKi4bhSS3l0OZWzWEHIATOwYwfjvf8Efs3LGfICDx3aLostw6AFJMPegEoBFotKwwbwjc+d4iGfB9z2"
    encoded .= "8SpHkBEFoDQOd9ARfMkJLKro7CyJKbQ6yDaNGgg8kZe9uHdlu+BI+UJgNCsp7IeTNzrsEwQtO0yAw7cxTt5P+O6fJzr/4UwLdft1mCNw3AlTsikA/Fh4DNMB"
    encoded .= "R25n/PYLR5SJ9d/AvlJWTtLs8PAfNHEJTJpIJICXlwTs4RpyDG2j1m7FKstgSo0n61wC3XVZfq2+cdxs+m4f78wpQJtnk8nxzjPgKDlWJpsucFfWlaRTOrnJ"
    encoded .= "SYFZDxtRpUi7TjrPSusOq5cRwweD2mfQFtPBJ0vfbdyTnMAjHs8q2DJSGyTz0M2dwJ/+ZsUH30OYzii110BefGa44hlfwaBChLoAhknFN15W8MSnEbZuFfqH"
    encoded .= "SfO8CLRNAQwg/f0KbacJ6wXBIUKJI1vKIwEEE1ljuNt2lRJihBcRcyepTCJqGAg4dBPjvAcQvv/FROfcX94QVAavGa4sJmFJeVdsgndtxMtfsOTr3gfs2AFX"
    encoded .= "SkC8vZGZKiOdFJ0AfR0vdLozqAqXCi5jNm4MqinC0Uwz7QM18hduLiXCswHRvQB2m9vqgt/JL9rmKsB29wKEPClVthc9rjw6Ypmyd5Ycm3B8UiihBxcr6G4+"
    encoded .= "Revuatnf8c/KCoB8zsLDiWntkPtOO4/8CCgUcq+199harjdtE8qEMV+Af+unKx87BFAhfSV2lAkQNVBMCspGsVjFWmVq8ZXPmuAZPyC269hRxjDVnFdm4gry"
    encoded .= "3ZlRaTTJ6Q+CTtnsJ3jbdzfW2tvFO5lP24EfYQ1DYkiBXX6XAVjOGYdvAR73VQXP+gUij/YPARR5+NCNVTMMJgTqiaAC93towe7dFcuFTDES/KASY0SlSkwV"
    encoded .= "8mNSeIdyCBUIolj072S/jDolSErMiZGWqEdp+N1r7BUjjYMvSSo/OX3O3WduKfpk17YAwN7eLAEg0vOftaOUiFOS1qEzdZ+aL7uClBjSJI7k8mZY7uCy3Gl7"
    encoded .= "LuQkP8ThibEzMiExpZKrdDb0ACKEaZJZWd7i8/5/qbj8l8bYKMRtVfpoU1Uu5m9KFvpoMWd65JcVevb/mODu5wIHbxYrT4X8FVMZWHqut1OqsD4+xjYGybxE"
    encoded .= "ad9pGBRTgFdOnM2CO+iu4EM3M/bsI3zr8wqe8SOgMgWWCwEGV9Sk3d6PteOdBg9AGQpGJjzii6f4zv9vAqrsKwnWcUr/9WOQOWLlOeXXCP4RAhBanW1PDXIV"
    encoded .= "d2/XjZ5NK30PUqoo12vd0ykZp9r7q/KduBnIlh6NsvRudR+v2NgSQtHuEWC3vs1liNjqpQsh50JSkShD5llbogu4MHzAuEPm5vmE944IaU4HNPEFf5hIDr4s"
    encoded .= "fsiE/wcwlqMcnf3aPwb/1csl227UDfkuu86yVSsXXzORLg1IXAA4+3zQs/5HoSc/E6jLikO3xbw1cgu6vmad8R9NemJywUsWhpR/bANVJe8noQTaoGYyRwPJ"
    encoded .= "ZqOtw4ytI8CjvpjwnF8r+NwnMi0WGjMqMQqdGDjhzQpSM85w70VkrGKxqHjwxRN8338fMJ3IfoJBDw+VKV5O1ekUihkkoXrvtf1Qd1CzLb1GUA8omnOZx5C0"
    encoded .= "Xu+hBWmrBdM7OQMab9Cnw3lcMsgL7+/EzUCcwFcZmLXCDnGKB9LHTuO5+2wIwrl8YyRj7uwRfWrrWJUaikExA5fNPKGrs9FC2/vt9SWnADEo/k8Cok6YCMK8"
    encoded .= "CuzYxfi9F1X+p78BZrOCcWlhvnisNczkgp9O8BHOqFItFxWTTeDJ/2nA9/78BBc9lHH0UMXRI2pF7LReNlhqWBBjkCJjZrHtLUhRKHVrBSA0E8PdFgIKEQrT"
    encoded .= "scOEY7cRzn9gwbNfOOAb/hvRvtOYFnPExrI0b2a0v9c0D5fGLCss9lambBJMvP+jpviBF0yxY5NxbItRuuyXUNMOfNP4czAFpga1gGohymcJ2LQgjl9Jrbgx"
    encoded .= "IqCtL+Q+WteERBkll7A1nqt8VN5t70zQbS4DJmDnSvI2Vm8wWYE1T+b5ipXvArqrEUZt1HPk/RmKBzgzcm3jiSryI66yEsSg5JJQcV5N68i1WsONFxIkNWWZ"
    encoded .= "JWtumDF+7XmVr34HY7ZR/JVjAQLJjFrk1b+3suQ3qRBQgfmc6R73Bb7jZyf4jucNOP+BwLHDFYdvY4xVgIAsQaPvWRoLUyABzGR2iexrNzdu3ZS2ajhYQMsl"
    encoded .= "6MitktJ73ucQ/tPziL77F4nOf6hYfXH5LWuuBRprP/M1c13GhxOIqQLC/Et5uAygxXyk8x5M9EO/MMHe3cCxI3IcuoV42skqozBx4dK9I1Q8npoT/tN3chAj"
    encoded .= "EZOeadioMoe35ZYoQLcxUnk8mh5nT5AS020sYjWzp+4TXdvLBFQjWYNg9X5iKyShAXLEiVXBarOa1FVOJO+wy+vpubxf6UFfFPB95ipMneHyyTNiF5O/3AWr"
    encoded .= "/MwUeGRV+kmxGhRPc0UMu1nA7C4lrJoMcvz3L/5o5R98QaG7n28HXDAsiGXOSPCud3e4wQMQoRTGYiEl7//Igvs/suDdfz/iTa9kvPvtjEMHCZMpY2NmR2Mj"
    encoded .= "1rWjf6mRtKjIluoq5UThJQm2JAs8LoD5Mfm9Zy/woCcQHvUUwvkPlxLjsmKxhEf5wTFRMifAE4goKMkf8vv3GqY4m1wShb5B4gvnXlDoOb8w4Z/9/gVuOSCv"
    encoded .= "ebe0avPCSIY3eQXS62zlTbxiCirLr/ko9zXU+Ti1Rk68LHZeyD0hQicn3lDOjyXnXb7KNl8Mst23A4sQ+4s3DXHMfKQlLmPSWuFdB1MpuMFoto3DAAeW7Wdq"
    encoded .= "YSqaoM/Wrjk15EJswqNfiSqjhXT2mhNEEQFc2d+2K9UXDSZRIPk6fnl/lZZxBGYbjMMHgV94DvP3/w+is84FFnNoymsM9gq3TPrIACzcA8nSkjaWC/E27vfw"
    encoded .= "gvs9HPj4hwnv/DvGlW+uuO69jIMHRLBnG4TJVA9uLR0oW9IMKHn1FPNVFgVabgHLucQ+9uwD7nN/wgWPAi56NOEud2VVfFmKK0VehJoBGcgK7VjbWnsgefy9"
    encoded .= "9ISiGtlmEEz+qMgKw9nnE/3wL035+c9e4MYbKnbsItQlxS7DtFRZ06HE2bRme5RO6/H4mOf35ymK8c5U1pFOC6gMhSNEIf/+eA4AhoE0vARt+zyQbXoAYx1Q"
    encoded .= "WqISeSDYjCBwyhXeIviaPRh8tsEjTarIyTpt/WBGhSzHOU0wQ0RpOVWhx8wKUoWM9DKItKyX53s6cLrNCCBdEnQXIUwT6Yi6peymfR0b/AuuwOZOwi0HGC/8"
    encoded .= "4crPeh7hrvcismUwF5XWIHvzZPQpL4sDMBOBdKWBsZgDVArf5W7A4y8hPP6Sghs+CLzvnxkfeCfj+muBW24EDt8ukfLKMSeXzTQMqhx73FnaLQNhtiFnAZx6"
    encoded .= "L+Ds+wD3uohwzv0Ip9zNqGQsFjLeVPSEJPO+yPgnCUFugZPO9JY0B+uSKiGbGY5RU8sJWN7pMAjInnVuoee8aIqfffaCr/8gY/deeR8lCGBiIn2Ns+takgYz"
    encoded .= "VMz6bkbrEQlIxjF3NhmhTg6TDWeAk0eQUj9Su94q/Ph8NWSZLtk8BlDd3rT+U/IAHHGA1FlR0FBAKdSfEmQjmne+sft+0XF3y1wZTfC5NQ8GIh1aena7z1VD"
    encoded .= "ZHI8QoxFgEPiu2lZg7reb9X8yiFgnJ1TSv11PthgSR11BDZ3ADd/tOJnn13wrJ8h3PPCEtOBrAYpwa8RFDRs0yLsNMqyGtO4hOSJF3kL0Rn3IDzmSydYzivf"
    encoded .= "doBx80eZbrqecPst4MO3MbaOEuZHgcWWdGS6QdjYBWzsBHafRDj5NNnlePJdgD375RBUQ7zlktTa64qI7RY0w0+UNriE8mf58o4hdzaBh/UxyYv0mZ33thTr"
    encoded .= "MEFAGQQUTz+b8MO/OKOfe/aCP3Rtxa694s0wgDGf7+2/2IWetTI3ZBSyX1I/7OCWwmAuMm8SDrUDaLTXlZGUb0O+jI/ZIzQ2WantZQJuczdgcXUMjDMTxw0j"
    encoded .= "YnnCJFaJr+2uKmiZ1Vd4tEWg6BoWIHQ/WwYRoLhDmcuarOCiF4Zcnw3FseBb2BNHgrY90S8ZlSbqm9Q3XJO4rwJdR8JsE7j9YMULfoD4O3+i0AUPtbfdRj6B"
    encoded .= "szeYsWIhnfeJgAGM0agugpzLhfFmRBlAp5zBOOUMwnkPMo0rAMaV2rFyya1xFPfaLDhBjkNripFVlykkl2fbpWSrDm5au2eIUn0IW9DzojG4ZnHtVmEsFoRT"
    encoded .= "70p4zv+c4gXft8D731Oxc6/whlKbAf65x+ROZIG8mLnnjiUT214ZGcPc79ZACc39jN6tTTM97q9mAnXnngnYgZDpBeLHyc6jwfkmB7fWMKcROYgwtdxVoNDn"
    encoded .= "ZKx6tnFiNoLfLoRaKhHdjI19sM8O/uRl/BcDnFwSgiSCUIqShhSEEsfSubypd2MT2DoG/MKPLPlNr2aeznSrTbIyRkKEihKtBhAU5QFGNchOClGKuflS02Kh"
    encoded .= "P/OKxYKxmC+xmDPm9rf80GJeaTFnWi4qLedMywVouZR0zzJopmTYzgaIVj4mvpgF88+Zwf04mmXvKu5tZwhqtuRRomhM4KS7EP3gL0zpvPsT3X6rLBGyz3di"
    encoded .= "VH31iW18hX9y0CnS2Ebuh7Yrw5HPz2IzkLRKdKNIMpg8hnCuaIOVb1bkjv/aHgDUTg+SZec8WAYKuTOwz7RmoPRzVsYORcio7U3sqiw0U41ALStGqe5mqJAt"
    encoded .= "uN/jNePCLXikUHwjaAV6nnzqbdPHGkA1jsBkKoVf/BMj/uBXRwyTgmECfXdfXCUhr/eCNAPEhTb1jaNMeEBWkHV5EO6y0yDByKEAheRcvlL03qBJRgMkCOpg"
    encoded .= "k5jVDUkDz45oUciXHBHgWAwhc0BXy8cR2rwiDu2V5/EWfNPJIGs68hLYu5/wAz8/w4UPGOjQAcYwNflNz1uwJ13VxMWmBhw/YEkksoS/Xp4i2GEraJ23keSE"
    encoded .= "mFIQJnM0rQKsLggc17W9PIBJcLzZzdbk2KcOuz6YoLc7Bl2BxVuS1QWTYph1pygT+KLtcC8bXnefXGFJHYENHHS69xE0uSVaM/DWRtV+ucdR7Vw/a8Hb7+xP"
    encoded .= "jJc8Jt9UTa3bsQv4P79W+SXPXeLoIdlANC4TU62ybCh1GMIEG0Ck6LgXTuPFooDR99ROn71lrMo6aa5sGhw/+4/hGXeJzV21FME6rXccJeAlUe/2AFrAliA7"
    encoded .= "69ldbo8oNuB4/02kiFBIgp+7TwJ+4BcnePCjCg7dwhgGjjdeU2aZvTKcbTHEN6j5uHMsa4LknEQ7L8CGzbZVO78al9bZBzWulP/u3+HoyEAAD9uDgW1mAiou"
    encoded .= "q98RqBYC75ZxtT9gZC8lcgcYUJ8qFlPYFMyfthayAclmH77EZ5t2yO6bdUlmm33ymIGIfLSTnYQt9ZEOlqM8muYbzucoifDBM74bZUkv15X+s4Dg7n2EN/5F"
    encoded .= "5Z/6rhFX/7MkDDHKHb4UMpjNTb9i4RJNu+6R2jPpl6/DJ0D0iANZINOkeQ0CZ+RrjL24sDXmNSvP1VEO7hgmGgi1ZiiV7+B0neWXfzlt8rU2shXRXunqwM49"
    encoded .= "hO/9uSk99D8Atx1I24h9R2OszLQkyKa34LB5Dkpzc4wxOc9TdCmEIDEsG8DWV7WxKP6XxiRB9U58MxCjylvk9OVyZr2crKRsnUwFOCgESHeyixYDHG5GN7QW"
    encoded .= "KLSHHILZ/8764MrPqvCNcTPVzkRSotdoa70Jg/Y8f8sKph6BNkZBEGt+eIre2Sm0fhpQ0iWuchrPh97P/DPfM+LPf1fOE5hMi5wvaKsbBnac+GZmhv2X9C3r"
    encoded .= "KhsgRg/S6uaKViWIh8e8qP++LdcwjU2WLXciBIWZMI4MlILZRsFNHyW88PsqXnqZnKpscB76Zv22pMSVLIIWjTMZLRq41A2DHHc+3Qk86/kbeNTjJzh4k3gC"
    encoded .= "bfQfAQI2tjoAbmiUEyGe1EwnsozqIa0rNGW+sn8K7sLqVpRN49G9ReITX9vNBKSsbx4hz4qfKGzXQXktgFMqaZwRLzbYwO3opva4OYSnvbS+NulA65e/LRFI"
    encoded .= "+6ZWMQlm1/n0a7VJ9eLMm9Ol5Lh0eiDzW9M9lrf1hMmSdlmOW66jnME3Lolf9oKKq94CPPU7B7rrveRMvnHJnj0YHFMwUUtDiWB3DAjpe7gVb5U4WL6WvXdU"
    encoded .= "jnP7tiJE0YbPeeUeV/GuZjPCYgv8uj+u+JOXMT72EWBcMnadTPT0Z02xXI7RR4ppg1TaTvdaAm1g8pctOpgpIGI5b2FK9D3/fYPLjxzFG/6csW9/Wh0w3Nc+"
    encoded .= "uQSZf6d6AZZEovAYclYlwB5vYhe5ldRshLzFOKTswOYbUp0syzsYrrXX9gCgQt49yp4OychmPI8Co0GmO8ypXzEl3fxmhSe5w+xN66NR9g6iv+Fur5jI1kI0"
    encoded .= "kUQXI3Bac7ESnJZHDAgHdQsD4Nqr50VkeVGUZyhoMPacBPzT3wLvfcfIX/J1BV/wjAHTjUrLpQDFUNoIvClLsNcUMAggd1vXpdaup9P62ZePNXGTZgP/BPxs"
    encoded .= "jCR/K+90Kt+9/Y3gV7xkxNXvqti1m7Bvv/Djlb8NHoYlLvkuosVC6TYr0VnL9VfIwUr6iPLWBpIhgc46MsoE9N0/s4nZbMGv+aMF9u5Xzwuugtpvzy7xFYow"
    encoded .= "hKEQ2Uu0QYnPLknIno4/nevpUbcD+opt6f82E4EGO3GQzOUJM2J5y0kbG/dFzY9Zvq6eKGN9YyQO5PsOwcFUspYjjz4ScnJKqJYHewxgJcTH+h3HgDgJzJ7t"
    encoded .= "FaCbta7Apji694btDECrhe04ZVCLWLnfQmQkDJEcArJrD2G5ZPzeL1e89bWML/wa4CFPKJjNJPFmXKI5qFOOs7I0hSRmVndKXk3MWclgzZcHGlN5AO5VrRNk"
    encoded .= "q40B5lHeN2AMfOebK171vyuufIuU2r1PgHO5FLp27AGu+NWKuiz8tGcXWiwkXYaKMmZl7dybC/r6/nj/Q0JtXmbbkseRMQwF3/FTU9CE8ZdXVOw9lTDq65gi"
    encoded .= "yahvP8ulVZ/5Yt5uMvFNQor8bRmCNoZ5hpjbIxBTZbCeNV7oTpwC1Fq4aipwzPfZb2TCOHMeadmME4tSvjsjFCW/DluLyd/ZYGfAMMW0wUhBQCEtKDMnJuhs"
    encoded .= "xyJPRXKZyilpk7BCXDThbXP2QqTK2qUs6OCCdUt4mEo32kRO7zjKctzufYxr3gf84o8x3+vlFV/4tIIHP7ZgY0MeWsyFG2QHs2pg052eDmiJ0ueue86AxnOS"
    encoded .= "mxkLgjF6U+tllnMPSiGeTKTM1lHG2/6G8bo/rrjybbIEumu3cE5eVRZN15Gxax/jil+tKFPGJd85yLn+DeGEjrGZKHNIUh/ipvQhrLgxqRRdjQDh239iA5Oy"
    encoded .= "hVe9fIl9p8ruzTDKppyquCke1UIor/A1hUGkr6zxwqZQSpMGImvWylTuDecnd4rStb0Xg1hQm4HRXX8T/rD/Ylz6XOr0keER+9bQ50BVHj0VKLvbzOsNCOSe"
    encoded .= "256VpZKoq+a6mz6ElBCJA1+TLnIyaxbMCgsQNn7IeABdL2avnlubmxkU7RdBB7ltigvZk8ALeRvvbBO45t2MF/34iHPuVfGoLyQ87IkFp55JLLGgSgtVFlvF"
    encoded .= "6LW9kRZDCM4ZeX2aW3y+o2kD1+DkZFrYTNJHrgHe9rqKN/0F44PvY1Bh7NglkGNv/CXEiTpyVJeQuueUistfDJ5sgL7imwcs55BchNCMVRDoTH6jW62D555R"
    encoded .= "/K17F6oA2LdcNsMwJfzpby2w99QBo/VRlZ9c+bvGuf+oeuLGJvFw1b9vphQ2B83YF62Zx3An7gYk+J4dN9GNaKhr3Cse8XqFjBUDctmz++hUZMUqkVGUNDSV"
    encoded .= "I07r3xTf2L85hhSeiZS12CBBAnZhnX0ouqmMN9p4JUQClB4LIKCCdOOZ/W/zugQ+srW029ioAsGFDUdqBW3uLCjEuP5DwO+8kPGq3xvxgEcSPvdi4LwHAHtO"
    encoded .= "Cl6OVbPKVFDlZCEDbd3MZcpvU6TkQZiyhWcVoC2uKmMyJTnpU0f2Y9cxrvxHxj++jvHedwFHbwNmG8DuPQBQ5KWiDAEJ66/xl5lJFwGYgd0nE37nf448zAhP"
    encoded .= "eWah5YIdqD6x3csJPZ0MJWNkI0pMeZmUmMHjEvjGH5thmI34o1+v2LO/YKzhBaXJsbfnnoHJd6bHRCWB8Br9V56s5qJw+k45Zl75it37RNd23wyUgo/GPSNI"
    encoded .= "lZxX3Ug/NTSXzVDssYFV8JARSCDAPlvz8hZ8Abdj7AOAsA5WXsfFKNAibv0bz8Ses36FV8LhRXgTrBFe8uStpi/RYtNhAjGL5DUaJk1llzNWFwqIaxXxnW0w"
    encoded .= "ZpvA0SPA3/wJ4w2vHHHameDz7g9c8PBC976IcOqZbPPv3HteLthID4+mM6ixQxLggTDxmWbDGdx2APjoh8DvfQfw7n9kXPMvjIO3AlQYm5uEvScBqGA7BKV4"
    encoded .= "DWY82lk1VZKNNKo0u3cDv/XzFcSML/2PAxYLQqGaeGrgleowNifnBzCPSD5bDfEYIY4EZ+JKvFwy/uN/3oHpZI7ff8kcu/YXxEtl2cFEGkkgkmy/pdDEQIeC"
    encoded .= "N8bE6eSWxXrPREVn/9tU+7i2OQXQnUYWCnf0USVMAYt89S6Ly7d+aahrSN8U7OrplbL3CrI3AAQwAIZZyfIi34/2cohHTgZOiUWUFCEFgsxC2m7p2nlK5j0x"
    encoded .= "gUofL1EGFctX7AczLz0kOY/4A/vx1oUIu/bIMwc+DvzNqxlv+POR955MOOOuwF3vSbjbvYC735t4/xnArn3Azt3E8t69pBENl80NCOneOgYcuZ34lo8DN1xX"
    encoded .= "cf0HgA+9t+K6a4ADHweWczkAdLZJ2LNXF4tGRh1jzdG6YFM28zbY/H5v30BQDMWu3RW/+QLmjY2CJz1tIH9vYG9B07iGt2fttFEqdxKV3zJm5i+S7v1lLBeE"
    encoded .= "Z3z/FJMZ8+/90gI7T9a3P9ew/rkqoz3osvczF65qcUKuw7TJ2QCO0QAoPIFsJ0gPxanQrJ478TwA1OWUJoOTmcAORRFThT18kSZ5B8niQWsxhVRFWCOAnEay"
    encoded .= "Za8vR+bi/r0BqHM53CR/Zk0gPoFs1OPKr380pGZkNsk24WGv05fcnRWJiDzTtrlw3mIQKKatEKOyihalVF5mz1ybToGNDTmGdzlnXPMvhPe9S9zV2ZSxczew"
    encoded .= "cx9hz0nAnpNlX/yufYTZDmCYyhwdVRJkFluFjx5iHL6dcehW8K0HgEO3MA4dBBbHxEMYBsJ0A9jcBMpOmTvVWkG1xPpoZwiy5vlUIo1dLeES+XSIgZ27Cb/+"
    encoded .= "35fY2GS++MsK2VuE8lyck8x4AJmyjLbj504dtYOlauru9nIBXPLdO2gyBb/sBQvsOnlw2fIOptwKfz+DmY1mXI1OxBQ61+NSFbJvhsw5UyRkxRW4U7cDy4Fy"
    encoded .= "+W/9ldHWf9mgmsZTeALJnWzhmdpB8ctZ5A3Z0PoBI/Z34xckpXL6ZHQbQ9r305RUqyJ73ki3fiall2kyhyFAtJGVO8OZtZ09xZGZCsAlE+UBu8hONBaFrBA8"
    encoded .= "pYjh0eI6shM/2wTKTvFTmBnzLcbR6xkfuw5YjvAXsIQEBb9tQlNIztgvumFoMhBme2GxE8GfChr1zVDFx4R8qDvqXckoK24O27MszTXvESRgYwfjV35yBBHh"
    encoded .= "855CmM9tQ5OlqCXZSuBht0yYGQjrasasn0JYTEQDg4vFiK/4tg3iSvitF2xh9ymFPSnOesiQk6J9UKRPcn5NUpqkstlQNrLJnnKkRBHyqcN6C8355cdxbW8K"
    encoded .= "UMpoxAGMxkIyAkKN8dVtonfCXqUc9VgXtHulA45oLjWEXKsXypY1YCLzNym/MjRZaPhSGQhpeMKFyysXjQsZo9UDirmbeSHA24K1JQ8aeDCYmJsIBgA5lJIC"
    encoded .= "gyIdwYYiuTPsHNX8RqWjVjcxAMkZgZOZ9qLhranQqiXyaLTyuo4sOxQj6dND1QHH2ZrGqPg41xivaIsxaCYR1ziM08SMCjCdMf7nf1tyGQZ6zJcUzOcVNISB"
    encoded .= "sSxEszuEMBRuHFj6ztCYRI4Qu6tgcgkFCWCxYHzld8wwmTJe9nNL7NirfTCZIiAfN+deIyeeOJ2ZJ9LJJtMWAho5oGyo1ga0S7d39BNf2z4RyNuhEI20NOwK"
    encoded .= "Xw0HsoIRgWz5ROQlsSDQul1OQevmMxCRzxWq1gYTgzxeuZMe1V8tsPh8MTsq2QVIMYZ1V1ho+atkIlOL3D1TiSn2DcjbZ1VUiAisKcQCwy4RKkDaXiECu94Q"
    encoded .= "8nm2zifOLvMd9SABtKqH3Q2opKZfTNnrYm3f+rsK3q1KaL2mtfIFi/GVXXWDerxlYExnjBf9OHiYAo98UkkxgSRhCZlXIuqJnGSAGykRTzMJNMlhqMsF4ynf"
    encoded .= "sgPT6RZ+7aeOYmPPkI6sU+VtVip6ExEtNyaPDbAMvOTA3H7KGuCqcdxS1lV+h9e2NgNVXpaYnzR2LiF9KHh7hXkMd7pbYVZBoP45FyQVOe7Q2xrtJDj8E/ue"
    encoded .= "UuFEt9bdjk+22Pova1luBzg1ljoTTZp+BJa35V1hNaQbL/vs+JjxSvWjZIjlxKZcXKGCklfhdaeuOKmpjgJwAbNMS8hOCeeS9rMan9eCLrX3omwG67TyQAYv"
    encoded .= "6MbKOu1WQiCn6jkFG4xf+LEl/uE1zNOZ7JXQdChfnW0ltv0Uakn6f8sc4UmH3crD5aLii75+im/60U0cvVV4XYjaNOHc5xQfcM6RvBbdA+mJHra+B1O8vnwH"
    encoded .= "ALgu77zdgD7kPj8yMgWu2uh/D1U1KS4DvkhGraKg1+MIrvQuouu8KiZbtbplNg4oTRRZufgQ7fjHcBFlESDc3pYhCVMS/OW3H+m82N+k6/ovykqViUJL+sgv"
    encoded .= "spSIu53ot6CrRMfDJfctw1reXxOmSgO14W4d+yUaMnBp8ARt3JxhwEA6H2BOyqztU/ojgl3GB3bvg6j3hKS8ncVfC1OVSLOsuxfo+Zv6NuCJvG3phT864m1/"
    encoded .= "UwUEltEfW5q1IcjtRB+Tj8e1g7Tgj70J2WghYizmFV/yH2f41h+fYuso607dKqszOh7yrpAMg+ky1lLrH2XpzX5Ysk6rRbdxbc8DgMwvxBJw0iijqB3wliwd"
    encoded .= "AM4sjyEPy0AugLkaqGU0r7h5FXjTDpKViF9Oosw9EggEfbmtuNjRqVF0brqWCAjiySeEQWvultHte4YgwSdTkMqgWkH25qhGbNnINxCwz+aptAFRTs8R5CWe"
    encoded .= "GmxUBW5VL2IUSTaDwS0PrG0vm4DJaGCWRU4TC32QkIcrGQTINKgxDImB4SmoYlQ9raiM+LkfWuLtb2SezuR+c94kh8+yeiW72gCGtsMaIExnMtgYDkPBuAS+"
    encoded .= "6Jkb9O0/vkHHbl9iObLLqYjRHbTLjfSkK2CpdwTzVFeWKVVvaHurANs9E3AhMSSZn5qgAQAFrIOrbF7pEAqRKUfwI45t/Remd1pHCjBmsMhKb1Yt0deEdpsJ"
    encoded .= "hsZo5Tw3pXnF8iXlRTxv8zB3zNwKtIieCPY/7EUTQRTBfW8fREYF0SjZQEZuIj1l2zFYVRb+euumbZk9j8xUQVQBEh63ouWAoNwslDCm24vhT/j4sINpC76s"
    encoded .= "i1CU3J3WEAgvW2AKWvT0HFJrTx0dVoe66KRCYGMlG3gYtTKe/5/nuOofwZOpbCyyCFwPpP1F6cfkjaBgRvAAoU8FwzUnItByATzhkim+4TkzOnQzIhiWDUzb"
    encoded .= "Hf0qyxHppi77IXO9TeilRe4qIwB0J74clDH6sPoczJVSTFkY0VW0y1Y3lFiVzCLwYTDUNGbHsHN/Uhd8esG5GAW/uJ0yGAh5dWFSk2KuGne/GgdGLYsmmRDk"
    encoded .= "8A+r193uRH+OdJhye3TdtIrbxyhBpLvbycIEXQqW/tok1ro4BMg9BWsrujYwuHBrSRqWe7WtRCduJtAMYbWpCoxuxOcKYEwnZ3azM28h+g4HYmGKguIITGcV"
    encoded .= "ywXjp561xLvfUnk2kzTooHGV6v6y/uaFLW1GH0tJ1CZ7BFAB5lsVX/TMKZ7+nQOOHBwxTKLCxmgRYjpNXpt7VRlrMyOa8c5DLL/vvFOBeRwGO9CnFdYYlExc"
    encoded .= "IzQAstJR81DU0RVXg9tagsbmdsuCnAt2zGGWzT0VlAaiXeqCiaWNaFNZSyCvfCU3imeQaH0uQda+nRdpsYVAdnYKGpI8MJT9GnlDkz2RJEXrIjAPNhngJikp"
    encoded .= "+s/RD3JKIonZlVaz83w+603piTaUOaT/WoTWQUf+tEQ/yV5kbZHJViRW+ZoY0fPH+xSFayXMZsB8PuKnn73A1e+QA0fGMbw+6ivo7nb2eE0JduPg29GF5yiD"
    encoded .= "nLL8tO+b4cKHDNg6YnsWErO9F8moZR42S+zB1Xx6NjWPq0zX7W0G2hYADEMpIN2R5kTmaG6mrMctKe4pm/4jvY4Zg9gO95I5hER+p8FowFukK6Nnj+2VLLsv"
    encoded .= "x1Dbyy1z8s8cjM0VT31t+qzPtHsAxI+rzPLSSCJ5AUTaiKBefQK48HWtj0VDsD7XltihecEBcpaAo8eN+dQB3PCrDdZxHIDpHbKHU92p0znw6HWoLPjLXKse"
    encoded .= "Gbcq++4BJGyBPUyVudR2eNx7TPxxLyiHe9UDq1UyEreOAc/7ngW//8pRz02w+to4f4DnmggBcXPPCesedp9AV3Em0wm+9Bs2MC4kUFnzK/UYKBXaz5gi9NjH"
    encoded .= "8Glki7yJeIMH7f+2zgPY7tuBHT8ZkX/S6IxZE4JtfOhQPOtLTmqIRsL62K3sroe7BYSCMKj7zqpKwJCbWOmctsH2Gc2AwBDWdDf1OXsfcjx7uw0kFCjc8CwI"
    encoded .= "5H1xu9paIEqVRd9I5+AakKboZw3hSWG4qCQhdiNZYvupegICcljEeZChyjrX3Gak2AR5OwBrenALCnYatHoajGrr/QEyPotCBqMYO6E15aZAzhnY3AQOH6p4"
    encoded .= "3neP/MF/YUymA8aR3OXup2LNUt9aQenGPAFHznCYDASg4qJHTXDq6QXHDmeep3FiyIYn6xeSbGS63G2iRHX2R9YbtE92bXMZcNn4KwxZEZClIIrIci8PLoHc"
    encoded .= "jBx1imTC5QFChAVrX59sD7Vd9lUGzs3RipuWXzTKLUlGcat0GdSsdc6lpfWwSNyAQPKXg76sNLx+IpKHtKJKfaYoVoJkmTJWR5R+XfvztpjdGquci1vKupRV"
    encoded .= "hIaicZ2qvpL8ROCOkDwF9yzSikHuq795OECoWa5kU3oGMftWklqSfLsbY9U2UIZeCTJyEhGWI2NzJ3DwVsZPfuecP/KByrMZ6bsWkjIR0G8t7gOn+UsDpCwL"
    encoded .= "FpPRYrxcArv2Es69b8H8mCVmOSNivGydtp+jKXV2/Hyk0Bv4uDuTALUGg47j2hYARPeNNElf5by+5ybDt6rBhZUtNNTVZxbQLL25pL6AjZRVBne9fR5pFHXI"
    encoded .= "TZSPCA9xcQbWEGSfQye3tuEkhUA0Qmzfa+aZFPDNPaTv1qRYSkwQ0XDC5pBBpXkiQmPkQ+oKmK9mMFWS9XJdM7+Dda7EPllfB2ShLYQ2hk26IeWKegUWobcR"
    encoded .= "J7jHYPfMhOuzTR9ZB5KLnqtv/f3/2/vaWEuvq7xn7fecO3PHnrEdSBBIbVXaosoVErSqqFTScQAFRCuVH720FIqgIIKCIioqtVIrdTyCViAVIZQKKKIFWpJg"
    encoded .= "j1SpLZAPUuIJFAJKyFfj4kCq8BEgduwYO547c+959+qPvT6e9Z4z9ow9Yztw9+jOPfc9+3PttZ619tpr71e8ItDJWjKLjbl9WZAORK5fkfap02dg4zwD+3fM"
    encoded .= "eOJTHd/7umP84cdV13tN3SdQtdWiv4uHS2PMvfP5tx8+UhmyqPjzX9Ry88dqHX4oB2mFdLGVzNgKli7aNqoy0+QwRjg/6fjO7puG3uRxwJuLA+h2AxEBlX9Q"
    encoded .= "jzl35PKjjqRDIu8Co6r20NA3IZg+FWGOurDWegJcmf1tr1h79ptN2igX++YLDU+RaeXWYN5+k9QGbLq7QvJRcZ8TFh1IrJ852vg8QlK6x55sMSyzKf9UuKY8"
    encoded .= "WvNH/wpNBDNUhjhLLH3GSkPstp4xy0aOYaWEL0ENIJQ0mNcv8HBCn9MQEHXmpo5Sv/NHEL4NtY5a9bH1qkmFzUZw5g7Fo390jO993RE++fvmGNx4fAlZYYW3"
    encoded .= "yowSnRCKCHAn3y7OAu5+5YQ2pfnIbaRTzyM1h0aNvqtbthokcVJyF13BTTW49jnTTVsAhfGYkYpgL3pB+dhCBP0dMEEQu7QW4EFzRQI8b7Yd5ngQK4mX/a+i"
    encoded .= "EtKaUE39JM3v+CoK0bBxw0yeINoiBIh1yPVWaQQ7xFD5T1BA0UsJlWQkZtZjInj/YVF0NHaN79KsYIMr6RoVQ/kRDZKZM9fwQnQkRpFxdbZ/jl1fbzyyjiyd"
    encoded .= "GMsBlXG6zcMWVvHzEdkh0fEasDvOAo9+ouP7vuMaHvtEx3qvjROTZp0RPhFNl7TYhoQ0gpfWoWCzcSflEkwy+VIIvaN1zXUJCb8Fd6h0s/TNLzDpWIKL2FV9"
    encoded .= "N5FuEgBamt82AhaqblZXt033YEfqEq8Rcw1IhBtfVoHmyQje2R5nWgeZLycj12dcd6I/N8dTw53H7m+MSRfyttW3hIAdvS+QXr9Q+7+Hvg2eLt+z1hlkSG0+"
    encoded .= "Iiyb7Rxkbpg2B5bOS/cXuKnaY/xLAZeYy6RRB0WMA6jeRC3I32UELGV2HxH3RbN3Ctt7H4268o32ZdwjoP5OERttE8E8C+48B3zi92f829cf6xOfHC8f6bMD"
    encoded .= "CnVMsYPL4tvCpclZrizSEn/8k8N63iUzS6iVzoFjTA2MM+LC1FE0s3bEdtdau26Xd6abcwKuECfPhhOp9N2cahLbQDnfW6OGj0RVInyfBUe4GPxiOB99FUrP"
    encoded .= "n4Kc24j5JWINlsK+aNAf7TJBecFvtnAc7zH5gMUZEKtGJ11LhKWD7GuFpPy/ioHV1CC9LXYZQjlXuwECzL48NB9B7VOew7B82Vufr65oPdYCWy64JNeI2/ed"
    encoded .= "iSS9BCArgLlpXLRCLhOwBz04RXIpOPycspMmPnKnC0/V5OgmwHgX4IgMvPMc8Lu/0/F9r7uqTz6mWO+1WMb5WRBSvqVv/tv8PAnuZDmKtPjz44+o3xEf86U2"
    encoded .= "fh9nHjlH8FXyDcbllM3MS/GTDRQml5N3+yIBscFxcIC17B2o55eMOKyMFUgFlqpiHFZxLyabiqjLAQKQYAAlZiXVm+uxFC7x2yXFWF9cFK2q4Hd6J2HuMSZ7"
    encoded .= "qmu+IQ2el4UvEyOQLL7LsQyNuau0j9PAj/rLTk3+7WnE0avIQvNWGB40Y6slV0Y+izklAkRQCjAYWpxgbpqaBLrgDpNc0Bs5JzWaRiADhjJYLlnKOnNhjUkO"
    encoded .= "we5SYKfpKNKX4ZMYYLLZjOvV/98jin/3Xcf61BNmCZQjt5IgtKBzzoPxqtJ3RtP1WvDoHyh+58Mdp06POAB/Q6jdMAa3x3J4Qg0ZucyxOGnsuDEZAbfSALR2"
    encoded .= "c/cB3BAA/LVX+Xy2p2yCR/ckBx+RSyGLQw8UXVgcQak5kiE0I1uYAFF+/IrwTCiBBtIDS3Wz1k1p4Umtn9hn4E9TIxpTgYlPZe0zxdHFjyyeOCCUwyKUI5hi"
    encoded .= "AZjEckFSCZsi++BtpJ6oYx1lc1nkdXlQTTpkhy+/B10yytFDnF1QfapjK7HZDgLyzbjBG8pjN0CFIrzb/rbo2mMauY29Y9ytJxLBTLJF0+VcjTY2x+PW5Ec+"
    encoded .= "tMEPvOFYn3kaWK09WIiUR2hkn7dUcjuYks6HCN79cxt86o9nrNYwmsmwSkw+xpkGhm8CfRprKh7mKmcPDZmE6tOjwEO4kXRDAHDJ+6Cbp7tdn1o6QP1eRps5"
    encoded .= "iqKN/eqkY2r5st3KpjsUGVGUbfilkfnCz22U5id1O1dSeyz67sLmuLRljhduXOrcpQZXohFHxmvm9vEMFabDibUQ0+ClIXG5kdijQynEaaUAsnUgZ/k/sW8R"
    encoded .= "quKNkXETETC2rmYP0AEwN5FZRELL+ggllxZFTS/Axh+LelDjcmJGnt4Hf+dZhpzduYVZV8axPJUqTBpKmw1w7h7gw+/d4Ae/+wjXrihW68FjQT7nQ6NYLBOU"
    encoded .= "oUADBFShqzXw9KcVP//mY5w+K+E8bjFIK0O8x8ekWG3Elu0C1ApN/R6QJp8GgFe96r7lUHemm/MBYHrSorjEEalqrpJ5DFNQB+qDXUisNPjbjivi0uZmrLW9"
    encoded .= "kHGZC2qiY4GmGl+RXRj9iFgA60cszBZmWQGmhZBsiX3+teRnXkoU5pQu9CTG5nWKirrDZ/nmpNqyZH9Lpu1ZCqvBHWr+Y2iXGseXRblcyIAXnzxE/ODSqgC3"
    encoded .= "U0KOs51sfnxZlj9e1tu252pBKAHO4SPaIjoPmig1aHW8Ac7eA7zvV4/x7797g6vPAG09zhTwkePBx0Rf5gfN391icX7mhzb41CcV+/sGdK7sdhtkCTg5yOLu"
    encoded .= "IgMWgnHgzFWdAtJ1xoz+FG4i3RAA3HuvdWfuj250s4FiAi2ttgdCCy8ljzMRyaUu5NzNId6Ci/9yyVAIIjaChZQtTd6KmPyR4cCXHyw8Gvv9Yo6aNO6WvCb0"
    encoded .= "mxCl9iDsCS1lxkd1xHTysEgbzeIEJnFgkpMAWRGhpgwCIUQdwAwFh6EarcuyRLOObsiTMewkB1JjPbAwV4nMcB9Btgmodo8vpwJ8DkOzTv5eXSi5mBAGOqAL"
    encoded .= "lbM2xWtpmDeCs/eI/tq7NvoDbzjCfE3GcmCWmEr1SgOg0kYUkfD07+0JHvyRI7z1wSOcvWtMbGsZTznmX+nvtFnzJxeSTemoiAiairZhAEv0p0PmfqQKeXyM"
    encoded .= "yu32Z083BAD3XxyNH633HofqZ8YVrd7xxSQHtxqR4WY6iknqk+8K1gmxC8DH3j857Mrv5DKvuTBC6R8FevDvBYIMxs1JyYfcs+0zYgLBFLUuQ3sX46LZdsOy"
    encoded .= "m+mTd62YCQjB7JF+QHwfZm3pmmvuHg7NCMTplNmErSliK4m7Ncr5k+GBdmAP0NZKkfRO1zp5qeGNiGq8OEEbBK3OfQAaLS6yvC0unXmciAGiCohESJxboR6j"
    encoded .= "wScGRvbRxuZYcNcrFb/xK11/8J9v9PAzivWemFa3ykUg0pDWEzD38bNeC9ZrwZt+eIOf/MENztwh0NmVmvMTCz0pCUFMYrEiCUWDPmqW6jR4RpugN0wKvSrY"
    encoded .= "PAEA9146WIrRznRD94c5udoRHkfTT7W2unvuxwm9nLFyhH/YrjAYLrVGOdMPWlf5K5h2trNs1ISxOPrIA88cJt5HY3KuIzhsUL4jPm635TX4Cr4YPOz+G+Nd"
    encoded .= "aqI2Q+2Kq0LSQYtkEIuuk9KuzUIKpsbwkqFqytGOgvSWmeAwfxtRpbt/T3O2IEqXfFON94tB3utsAKRDh+DTtuZiOnmatIhu5gujjY03+6LaWloaELOooMCk"
    encoded .= "I0BqPhbc9Qrgf/+vIzz6zQ3f/D1rfMmXT1FrRMParK9WOV+/91Hom3/4CL/6zmPcdTfpVkkv/SwQGSfBxd8m3bSRQ6j8ChpvW7XM54oma1H0xzeb+VEAuLg9"
    encoded .= "7TuTPHeWkS5A20VI/+6/e/T2VVu/9ng+PgYwpSlNhEVOdAzIBLy8RNGEbIS5O6Im4hfRcS0XdKClBbXpf8RWIPVDrZygPmNdzSKT72QTGsxYj3fJN8qNng77"
    encoded .= "r+kQZlC9HhbrVdfteIXMUDSg23WyYrRyU3ZLI4Tmiy4lEYwq7iBtXXUExlDYhsCCAzSO/fXGdpu3JaXe8pU/6ZQlJiJzNXvVpw4xL7sBk7ct6XoJ14KV3zr3"
    encoded .= "pi56OY8BACw8xB9+Nb8H2cQOlQ4Q6OJB3qnV26S4+gzQteNv/p0JX/l1K/zlL55w9yslXm++2XR5+gngYx+Z8ctvnfHrv6R69RnFmbOKePWZO0RtOgsVnbwx"
    encoded .= "TwI++z8CAnOvgYPWxOhmzr953fbX8+bw8pved8d9Cb3PnW78BtHzaLiMDpEPi+C1BVpZ0kGC6LrGPKZbPQrrbVcAcxKiiKfNthZqUuBGZJVaxlA0Lvjk/pIG"
    encoded .= "3TmsEuftpnpyOnUDGdFWJN7GqDRm76JAmoL3yHMMGdCTXTbEtyyt26ZIvEHHClif50b1MkkwOJL39UfRBBaR1D7FnWkgFAZBmOQS/gIRO7zD+wNE99g1Y3wl"
    encoded .= "qu36yzum8cnoF/MwBpl+XAJLHdbJuHk5Sw9pcv7wbUhF3wCn98fT33hoxnvfPeOeVzTc83kNZ+8ZbR0+3fWJR0ek3/FmvOL8zJ0CncdL3ni7OWeG/F6153R9"
    encoded .= "GHGQRod3saLPjwoEXeVDAHD+PKbLl7HZQbytdMMAkLEA/b0a/cvJHEzF3A2k66KSQfgxz7GXocmphg/pTmVSbYOL1x+BMI4P6prb0NSdS9TL0C8ugDQGBZuV"
    encoded .= "MVACAYlxedmIfIO9J8eZ34Y7t6obfHupEaMmPmToa9wWanIs3n6iy4LYlUBjmR6TlwS1dtXp5yAQGpYG4MP2Jsjy8l/q2zoaNdmBHVcQOd+h8bXSNM3gakUK"
    encoded .= "EELrhmReD6JBCseh3iCtkyfD6RW7SwS6Zm2cPTvyXLkC/MkjM+aN4UYbL1U5c8f4vs9aov3c6+/AV8iL5TOBH89mqjoIDzFPmvYGybgXFduef+8o9xBuNN0w"
    encoded .= "AHzEdgLWk37oaHO0GWWlDzZyLKPFXwwxxhKI1sObzmi42MZCLouE6lgyH2H3aI/XAdYBMZTvrI/CRMy+LxOHOufEeWs1si/kh6oJTaUeebhoxQXGtKUAmGEH"
    encoded .= "WTQZdGgmM9dlnPqwQyEjQKfVBoseIQQNuFLYyyv8fEHmyXfnuQbzJYX7Z8aSjSPfhiVR9JaNm6ZBsxFzhNmbVFOwWSvwLA765QC9L0suC+vOBV4aqo9i8GZv"
    encoded .= "KhK3fscsIbhSiH4qsNecYWqC6TTQVFU14yMyYGmHJesEp5YClZQppgH8wSmWT+wdymHhIKyrgRqKaaOHRzrN7wOA+y7f1y8v+3GddMNxABd9J+Do9z4mIh+b"
    encoded .= "prVBOelB90iZPFUsS00L80rTajx9BpavuHtiLZxkzGkreBPw4d5uhVLdlsNN2NIDgUdmsaXB0MCssgQMiToQ3BN9CwugGjz5bEyx98u3msMxN9u5cDto4Icn"
    encoded .= "XBPA6lhGWgtQIit9nHkAT0qHWB7Y5K/+HI2xDZJJ8rNnRrDrOBfhz5wvFgC+nNPxheTZDQelLfQ0+kDjX2W8OkflPsrCUzU/a2qlvjkpe5dwBsYyZrsyqPoR"
    encoded .= "/1RGUMXyurNSuSaYiAOyP5FaZkR7a1/JXhPob5/rd34UuHEHIHBTgUCiBwc6vfFtX3RNBJdXkyiEj4cs2Nv77Y9F8rBESAYzApn3Vsa3b4IgQATuDOI6SioX"
    encoded .= "q59zhrLtIoX1O15vLZfH3D1vYXmsJ4SOnvIGprgnTBb9WoRDuqzJHAQYNXj8PcwJFAPWElVpGk5FoU1FW5eI01/SaQvtQlAXwLyY4h7CvIC12D7YFaEZ9zhH"
    encoded .= "m6nRKy0Hm+QzlpMsFxZFCnbkywFEN8W34sbV43a4ZiwrDHDU6FksTSKYl0sm3cH3UYaWlwo0u/ij2SESb6ELZBaJqwDUKpBoZnxuknNmFfQma9WG9/z4++T4"
    encoded .= "4EAjRudG0k1FAh4kOd5qFmnLba1Fm7L9UWA39JiUMIMt38Pih20c38czXeSqQjry79axCQS13RTNrGQ5n8t0Per6jEaduvxW0aUPH0So+ZF/tl30ijzMuaDf"
    encoded .= "qZfKjgoNWYW1iW5V6QJCclEHuAQBP3PBgBp1aQgb07VG+HkxKWWX49qaPi5aKZ1KMyEqwFZ3zeHWmOBLKwA6hDM6h6DN1KGtj4M4la+LpNtHtqo8eEzD4nDA"
    encoded .= "cFIUpdcatLUIVGBlsouzjRICUWki79jx9XOmmwKAr780LJp9feby8Xz0x01Xq5xlYqTCTEnTeJ0xZ1LEVdMFAKiSMGPNTlCM01S0WtqWSpoIXjEq/fNOe+vB"
    encoded .= "hgupSAZclAVpqtI4cfdCQzqglTBqE0Q/j29h/wvO3TbJw1rx5owQKrm1BQu97c30m2slmpcoT4LNA/Ks9lIVLQ/VnNcsC+pjyqxhjtjfLVbgUq0/x4At4Mg5"
    encoded .= "WAJi0krKsyUJ26wqcfTUBz/61paTGtUNEyoacQvK/msKu43IBJsdV0lYuLHBbfgffqei+OAtupUdnQQ3lRiyWh/3q4/1vvklALh06TZeCQZbBnz/z9/9aYH8"
    encoded .= "3N7U0ERyu2Gn5hS7BdYmjpG/SnwJ+vIorxr3rrUcLfuqmJKdBCSDMRB7Cd1F4Gw3ES23wpbKcuzjjiMtGrHjI1wzA5IEldXdqYOUaCaLMUg66apUCmcU3iNA"
    encoded .= "AEu8ZSfvyNrqewGksJSoLuQ5k1lUZqiI3RXmMQSxNRU7IFXwq+oa3/G4uM9MiwgLT9kblshyJNHlBFae52bYM0g98nRuBzKuJIy3EZnmbuO3RdqJb/+6k3Dc"
    encoded .= "xDME2A9qOQlbH2+h8rBpsUsywlku3tYYSwmpC93FCm4JzgJt0lfTaYHqO97yvnOfOjh48KbMf+D5XAlmacb8QB/B5hOBFbivsEGkzx/FLKQjH9sah4SaHS3O"
    encoded .= "8zPYEc1IycJBT41JUwRzxbmLYsLCScK3hICtTxFzYBw7V+EOHcWLSi/LPO3IJLL1jrxtbZCMVw7EqLXTyKYEf12hKb5TZfLDbz5j1hJF3jyMFMyihT0vm7rB"
    encoded .= "x0KWM7dnDmLtdsi/hE2VOsbn6oeJ+owWqsOyisAtQoagA4EPX/wijMSLOVwiKdOmgfpNDO7+rJgaE5QCgGVwEqCaedz5q6Lap95n9NZ+ZuQ/wM2mLdreWFI5"
    encoded .= "OMD6868cv3cl0xdv5vm4q05uApHlU+kUo6iBQUyMREUNZtaoZ3xizSKx1eObkV6rlD7kU6s9OC6BaBcxbghONbeRo58KiIUAxuWXtn1W4ER9T0GhZTvN6TTK"
    encoded .= "qdjrxro991uBVEuswxaghhRmTEMANAf9eB/8ewF4h1BkOV+jP90ibzLIaIHkBmJbbS9p63NK/XEHGBmPIai7ILhqEWC5WxPWnuTfW7QifpPGdS0UgJojz4p3"
    encoded .= "D/mzuqfi4vM2JHxd2ornAIX9Bx+ov+OHl7AhAw06yd40z0e/NR/d8SWXHsbxzWp/4HlaABfOPzRduiRHU8N/Xk0tYCm29nSpU5gUOSlKxC6acAtuNYEF/vf4"
    encoded .= "kulcaK5VL1Th5hCeUTIDVpepaheBk5m5xyFEo2+KvFKbOgjl4HimDZnxHJ3n9sQAGQtzE2fu1CvXjbQ0Woz5EQJnKWTWZbkYo6KGnyGEpNv1XgqEae3ll87x"
    encoded .= "ZefqXC1+rIJcYzCw8axlXbwadOde5RnuBlkoWwOnvMHTAQmFZ9wBnpeVpt9jFhU/wKUQdJG4CF5N39HKf7tdGVe/cZyGuAUrgKpqw1pE9CcuPSxH588/dFNv"
    encoded .= "BNo94htMrqve8DVPvXKa9j+ivX3O3DfDoSpAqINgCNNaTkjNa8AGGZ3N0xT2NakC40YIhhMHjrSns2dKg4pM+Wf+4QwzLlYUrfHwWWMFJRd+D+Mt5rdrEMYv"
    encoded .= "E1bf+mIaRB4Ys7tm03GSLbSmLOuUKnB1mNSPhQ50C0OHRk9Jl1J/ENi+873+7sBri2CuW2muk0kRHQ94I5gN2jIQLGdAKOafwD2/j4aCF6Jdn3/vq2aRGKbR"
    encoded .= "KeMOkvciIKsUSJqJjrW9v3LOrahhPRlHF6VMO2YUG6I1S/2ofu7fLD0XpdYm3ejjs8z3XvrAuU8tiHfD6XlZAALRBw90euPbzj3We/+p9dSadszZejpEvIQ6"
    encoded .= "YqICfbHtrILwd7i6Cm+3Jm9avnx5iMHmaH4b+TU1BNdheCVzk8KNFenTYRcYXzjSxxGGK+yEq6We5QLxWWMr4qUQmsdYl+BTxqIo35UljTO1P3dQKlYCAWMI"
    encoded .= "KaiumkKmXNZIaEkpx/jc8ZvXpyXghwVihfnuP34VemwFc/3JODYPCSbK/g+3lNTbYPoo0Wjbg+CDdS0dYBvMk648C81UQDLoy/0S6oCRFB9ZpLSZXBPECifi"
    encoded .= "0Au27tfgvXmNfRHoT1/6wLnHDg60PR/hB16AE/Ajl+5XQOV4nt94NB8/Ock0Cc+tp1ATPuH+XBZfS0zaLrtEF79rA5lrW/ARnYqdnKiH/8/6ltowQYUZZ0fn"
    encoded .= "uA4AuRSSrfxOEjcjE2CoFiWw4W9Ke2z9WN/jCq3MXuwgSVArtEIF38DVIL5NjstZCBAbs1zAQNEe8Q5ciRGgHvhC2rljKZhehMek9DBxMXPwOx95oHUeCRq3"
    encoded .= "GChFNbqsFpWJtCR5PO7EzfMWNJJFswrE7ctNx8+gG1mKuRumQFsdz4dPSWtvBFTuvbRDLG4wPW8AuIiL/cEDtB99x5nfV9U3rtfTBL+fEWDgu27DMc2OnLkC"
    encoded .= "QBKsxNEVW3dgRmG9avJaKf+f2b7iMuzbnCjXGGWnguoO4aAWIp94W5nHgWWY5bbc0cxXBy9UDvV7b9H3jsOKkrH+qq8mDvCLOhb7TaxhddEftVnybbOgr9PG"
    encoded .= "BdupakLm2jju1fP2efpCFk1jkvCMIWXIcqX9c/A6j4UQUGmQhQdUkyQGUOaAU6jdu186LDlWd9I1lUpz/sPKxYUnTiv18xwqXeOixVhiWR4ViDaRuan0JtKl"
    encoded .= "63q1P6nM/+HN7z/zuwcHaBfHPTHPKz2HmD5XUrkAyB+89k/u3sf+B0VWXzBj7gJtKUA2oFhfIVHSWWqhBWKueMoZ4d1uBxAH2uHrLh4aO3CqQHlI0fLZ6CN1"
    encoded .= "yDleF8YMqD9RdtQS/fVCNLbCKJIlGbiKMFBwiTOebLUfKrnUzSOvo6U+RBed6RYDdFPW+wIAmu/hcipvLVaYhLy4YpqFoApiHz3aIYrUbiBMMjKbeUkk17Pi"
    encoded .= "InudB+6uQCzUemQOJ5yQJUdLCkFTbRE0gojkiiOI4quCBCJrzK76Ilax2bKicd4/SdGbTBMw/2E7c8cXv+lX8KQEJZ9fet4WAKzhhw8g/+kddz+Baf7X66m1"
    encoded .= "VH2JZkWeCAjG8dhq/RctRILgpqdHmsWequbPomv0x4L1dYderwtZf5oVLzWXuvYquRO0IvSGvq6b+VkdKf/l7gnZ36UD1UoaB2YoZmkxEglB59Zr1fyHlr9j"
    encoded .= "ZL4up/LhlwmB8NJaq3FLbZcl7IFDZht1Qvuwskhzl/MHRZbrHCxIEOWTdoRMRO6tw15LRnM+HDsV6e4KHpKYWMlKC4VBdGMrzaeiG10inmTQQKd2WnrHv3rz"
    encoded .= "r8inv/4Az3vtT2R54engQKcHH0R/w9cevWste+ePjo+OddyyNAZptBZBvN465IrCbdHt9BS5vQdtnABWJhRDOtR8MMslANkHoOlZGNRjMvLtv/aNZD/SnmDG"
    encoded .= "Wwir18mAt/wQwmY1ypaHINuPXBRi6k8klxTRhNqLPKmuqNvGJ3EGg7RYxB/4mIlu9Ct3FciWV6NCiXEgxmdhIcBIGjI9uN9K/zsA1FRulyLSetfSEqgg7go6"
    encoded .= "CpCF6tGc8SehJLvuHLhTaHMMonz993gctw55V7otL4T5KMcKEbBloejz3nRuvelXfv6B99/x9w4OdLp0SW7qJSC70gu0AEa6916oiGhfHX1X181nRFoDVHcz"
    encoded .= "NsCTnfu1tFxAzVcUSeEV/iaf5Dds4ucKXxa53Qpxto8yYfruaMAFJfoNEsj80Qjs5+TjElJxWYe3k9ucFQBdo4cbz9TIUrcxj3sFGmHZSEVF5sHSMci0XizJ"
    encoded .= "jW5mrzLoLSyRwviLcebwliBahVskQiASlBSo8ClhITp4sDVELgFqLoVfiH7cLucr/KWwt554KUX13O9a71t4MKGStxAvbQ0d4zEWXSesm+rVz3S0f4YX6Pjj"
    encoded .= "dEsA4OJF6QcHOv3I/zz7kXnefM/eajUJxiuK6hHg8TGVRzqhUjEkd7gzFJDtDfodtoszSYr/yKjPUsynfDn120uKzBcoDV0wE2kBHueOzu60HLLrVSeQsFSw"
    encoded .= "RNG6EQd/vfFqHdf1elU1poSMsDtMNJ2QC5yiTPR8F7v6c8EC+JeZFtbBrqzRRwGfyFvMSIIAWaGlL/Rntmd1uoMbCMGGgcBE720AqpWlihFO3Yfmj/4IWWsO"
    encoded .= "mHYeQYfTxpcH86rtT3M//heX3r//Oy/U8bcg261LF87r6uJl2XzXV1/9r6dWp77p8NrRkUJWqqk93MFRzMHoRUb2CVCPNYV0SPkzeUjtAsY0bXcd3tmdEl1Y"
    encoded .= "W3m97vwqVqOqvzAXsPPky74Ovl5wotb++HhLX0XGFuBS+6udotPxRhz1L0SqkeFLF2pTa4uVLvTALQv/O3Yrivqk7xZSoxSWHI24dcJzTmXEMc4ske2l1VaF"
    encoded .= "oeWJQvZt1dTc9xL/aTRfOiivlwQWik1Lkd5UxOfEA4EISHJ3YVFX1Q5R/0w3lo+6BF11c2o6u3esT7/p0gfOfdP58+9aXb78mhu67+9G0i0FAIXK/YA8doAz"
    encoded .= "7anNuxtWX3q0uXaskIlbCzFmxiItoCSFTESaPptAF1ETVKunMLHdw8eDHfnTK84bcRFiW7DJhCwAwkxpD9cT0kp00Um2Rwy8pdAWmgis/SNH8DzfJmMvxkmz"
    encoded .= "1wngDSnIOh/+BmgdbxDMAFMBuokm+1IFN83xXIaAiECWFEZ4aM6bq7UEvBDtRbu8C+T5PGoTULqcFVRL9oPBOsfigKoxDm/FfQbenltcEIkr2zzc3bbpRaAB"
    encoded .= "AGMMdexOGp52gQwnwVIZxKu9R49613nVzqy1H3/w8Nr+q7/0ETxzMWb11qRbsgTwJBDFBeBHLslnNpi/oeP4yUmmFSy4LeaeUDLfuGOmgX8Z85qMN3yDahpl"
    encoded .= "6d4b2fwVVv7N9WBdS0l/ZiztTXp/7VvX+n3WeAuMWxyJ/DnjW8sIbpxALkZhZcZLOXqY+1kl+TQUsa70F2rWyqPXKXDqAjROF41z/J3Gzr2BCS4JPvV7y3wW"
    encoded .= "Fq4cR1hJi+y7/gdADl6jCRgQ7ZwELXVCUpehvE43slwS+HyZoNF1MrYqFSkKld8EjaD/uGnJXw+/MO8IIJ1mNew7vE40hRYp2FfTegXMnwaOv/5/PCJPVwrd"
    encoded .= "mnRLAQBIf8CPvf30I5t29I/bJHNDQ9hOLhyWX3jgCzRnMR4P6qwXREdOcHWGcSBRrU8jL6O2oHQUC+Gm4FY/nNGEx1Fhna2ZKsjV6ZlnH9zKSG1E4rE9kLiY"
    encoded .= "jlI0N9oY7/c1rUL3A4yRJq2yGQMMo7UPgQXC6wf8gtHMG+jXK6wMOR3CV5f8PAdLCQqpgC9HfHySE74AJS10T4vbBY2AILKl8DIYjGpyTrmNpIIvPZXmLCfJ"
    encoded .= "lv80JqcVATVvJ0J7k0kmTMe9P/MND3zoro8eHOh0q9b9nG45AADApUsyXzivqx97651vPe5H375qq1Vrk8EgyiQGCbYYIhmGv/ZlUv5IDKRu0/BsViXmxB/I"
    encoded .= "3Fk+aw+CEySZBKhRy01IJrZqyOfcCP3w/ZApYHaIpCrlwazxEgsCJgen8lkL0I66FeGA2dKtlFf5p1pbAyIlbsFJEzo7Kxjr4mYWCkI4FJyVZcnbUOQcqw5L"
    encoded .= "2c9U2G2KKWzRby39ZVIwrJSgbJ/EJekoPxQQHdt1wzmXRdxuGnbvAoCdeQgY25aZoVa/z2kstjq0ScN6mjeH3/Lghz7n7efP6+pWbPntSrcFAADg4mXZXDiv"
    encoded .= "qx/7xTM/fdyvvH7dVqsmTaVpF7/yCDRpCGBE/GJNSr8TW8e/RtPbeJK5IJJxesI08sYh8rtLXRrEt4RWuS21YDPJkM8ADh4YUkuwIAi4Piw0XxWvLpB0oC7M"
    encoded .= "DR+TB7DRzzBVk3qK8f4/v9IrzGsmHpcRsgRUx4Wl3RxjOt5Q0jp0PM85VdJb4X0PBDP68oJYan9EoZMiXytE3cPy2ZZFk/3I8GsrZwewOLIy6836xpVgpqUx"
    encoded .= "rJoiOCKx9s9zEYilbXNhX/SMP7nwizRZy6lp0w+/9Wc/fPdbzp/X1eXLcsucfst02wAAIBB45x0/eqRXvnM9TasmTUR0DjB0fneBjEsQ6PcO51Kmpf7ZFee/"
    encoded .= "YAfWEC7X3QUHNlnV9Eyh3t2LilaDBXxPN1jQTVIyJ0XHdWJ258dgrpB4QsOiNXODVJvSBkQ1K9P0dVnRvL+vCE6ar8mpi3rYBiAV7U4xbz3OhJrGG5cg7xBc"
    encoded .= "pHUX/QMQB5XsnB1bD/69a+8ukACXxaRo9Hm7jWrG0zpix8QqzUNsB27bEwP7fQmw5d1zJYMI0Y6TkoHV2gVtWsmpaTNf+bYHPnjXT91u4c+R3ebk24Pf+TVX"
    encoded .= "/pHMq5/ULqdV5+MOmaDOpDYNFgASWyWEBB2VkQSVryIjttf9wLhGPKzgVPchmz7XKQiyaMD0OnUjwCHMVGXFFv2hBV46gyzTZOuA7uZL1J9mowD2AopRybiN"
    encoded .= "p0sx47NTVWDBJnJ0iajoxPSdlKRsWu3ks/Bu9bGzoCLjBhwdhPUF1hzvCqOxBA3ofHs85o6Z1lSMM0n22izeKCsOSjdx4vMYg/s/w45ia5OzLgm4TMY0rZs7"
    encoded .= "y7defRxw7lCIXSWkvgFFl+dz8j1/0T6vZG8tKle0HX/bW95/9mdfDOEHXiQAABIEvv01T3/Fetp/oGH63KPNtSNpsmJN1JnBqJN5B33mzW/r33qdb2OC3AKw"
    encoded .= "2Xf8GSBAa1GrwJcHwXBK1gA7wEIrWi8ykrP4bnN5oFtjjZGotSsjv+RDy0OqPUCDrB8hsz/KcTj0EFT2QThd3HwFnOYuNASI4t/ZQsxMdJZDBeKkXIzFsYVC"
    encoded .= "OkvEH8ggVj9yazcmC2K5x+X83boucKJQlTitWy2NmD+nkRYmkUIjhAUX82chvLsEOi082yZszlpB1cjTFDqPdcNmr925h378R70f/cMHPnzul18s4Qdu8xKA"
    encoded .= "ky8HfuJdZ3/pEIdfobr5P/t7p/YadB4bUik4YXUVyWCxzif5jRuq1WW1TBItJDcWWNFlveNh0TZW01AAbp5qFla1pYxz2xK4yFRPTGEcDC92XuxhW2r15Gny"
    encoded .= "FAldHYtmsIDAt5giJ0fyec8cdOr5A0mZXexEDXN2GO2dKBpZ7UPFMEY+65/NSdybZ2a+BTwEySJETjIwagmlzAVBX4W9MMWPAhPtyC/E0+bzsEVcGmcUcKsV"
    encoded .= "9BsOkQurbJydmE/Lub2+Ofr1vrn66hdb+IEXEQCAAQIHBzr91DvPfviZzR+8eqPH/2W9OrUWWU1Q3SQ9bUbVGZOEz4jsuodTsh3jR67fwwwsvyQBB6PuKkXZ"
    encoded .= "XiShuZaS0b5OXuT15ljbLrbVwIyR6/At7CMvMn9b1vx2AUm9/0JyHVtiaDXKRGfN2lFVe58AedqtD+mSJCG3vvU23rYzN4n77LrULTAfX1o1iBVH0KQLtc1X"
    encoded .= "cue43LiaG2RudmuygUJvObsdYksnDc+pEAz5HKk2eDBvdcZqNkadFecnBl8ZfZ3H24aCqLl9EBy5EUzTerpzfdwPf7zf8dhrHvjI3R87ONDpxRR+AJXPXqx0"
    encoded .= "4YK2ixfHnubrX3vtG9GnH2qYXnl1c7gxBrMpNPFXpBOo6C8+5+7Pt6FB+akqrflAH6Qy4RLuuUbTIP4imTR7F6Zm8JkiQkVdeIJp0mx28zP+dhDxqlRDwMto"
    encoded .= "lf969sTWQjozti2hXethf1Nw0sdN8QSEMoAkK9VkbgFeb/gzJ5W3IP4304rBj8YSlgYK2evjEbWnBaErORqgvfnOXo7ReQ3qJ/0Q72f01BsE4xyczZ3E79FO"
    encoded .= "76qKvXZ2pf3aYxtsvufSB8/+DABcgLbbsc//XOklAYCRVA4O0C5dkvlbv/LJLzwlZ36gYf0PVIHj+dqx7bK1DK5gIzXqABuvAMJszXWfHzHObLztkxiQkDKe"
    encoded .= "k1ZG7gSI5fXFBtzPRV0hncwmQDB7ggK363mk+guIk5nZeHyRl3ZQBKm43H8QocAuZNHfrY5j0RoGM2v+aR/K0W7vKgFAOWkbIEdjVpRt12iiq+aLT618IczC"
    encoded .= "UuOuOvD4WF2Z0LHyEQjIZ0eouNeRHkQ4laDxUuOgmSoAe3lI1GMmohXtCtWV7K/HdtPmwSt69C//+wfv+fgBdLpkUd07RnPb00sIACPxuebXfdXVr4VO/2Yl"
    encoded .= "qy+be0fvR8fDt+Q3tI/1YV3F1lTtBLYgAD+0U1+3zEK22D0IDenfDSEY/J2qqTiWrF2GK1aKzGH8vZcbzeaChceYWsnyRtzs6FcCAIkZC6D/VxVb9mCnFzxR"
    encoded .= "k0OuDfuMtpLA6pbaLqlKtC2zxL4GEcDfgjxeZ8ZWlYO705AII5VeSmXKMo/G7daU8wj3OUktYb2n0ZLvEfQ51YZ0UkR70qFdW9tbr3AK2q/9mk64+Jbf3H87"
    encoded .= "UHn/pUovqg9gV7p0SeYL0Hbhgrb/+M7Tv/DEK1Z/u+Pon6pufmtvdXo9tf2VqnYAMxY8vPuTy0UKmbq2KxwAK0clhZ+RaR23QiV7DWUq8Dj8XJd7GRSGHIy0"
    encoded .= "Q2tDEIta1joo/Ej+RTFHIAEblPqYIywxAMuRs9qObSzX9KzkUwNGP9THbuOC7ay4gPIIi0rNOktffH/dohSbBcrn8W7ApzCA3a0bQ57CCQQ0Rp38P4iR24jV"
    encoded .= "RyvUVhIwdlPs/+7xDZLn+K1/CtUZqn3C3mo9nVtr7x+bceXb/srXff+Xv+U3999+Adou4EJ7qYUfeBlYAJwYEb/jb3zijNzzed+I3l8vWH8JBDiej9G1HwOK"
    encoded .= "1odEjTvbWDcNbc0m32A/c25B4tjwEvnZMQcMAOgG+2lzmHaVjNWHaRmYWen353Ov2IzlE2Oerqed87GWv9mfR/JJTzTagxopWqMxk+Z3e9nqKX7QuN9u5Imd"
    encoded .= "BbcKSj3bY8r4gSq8bCVoXatYVKDUiqirDip8oIa/dmAqF584EIn3SQKYoo7SbJp3PuuF0GpWgGeT4REQaeu9dhZAx9yv/V80+dEn18/89Nt+43OfAl4eWp/T"
    encoded .= "ywoARkrfADAIds9j176mS/snqvrVq7Z3tyowb64qBMemPJto3FGRMiTJdEPODaWFDG8tvB8amJmXhXnUJgEAbIEEb2oK2ShgLKfYcmSVkS/lSLP2XdY5BzQJ"
    encoded .= "lYmytuSx/XRIE7IaUGhS6MbtM0V1mZHs4lK+wKiNzcHYAIB9B8LCnEaHMhJROLJ/yJOhO1qvBkeU8S3OMfi0mjzIrAJreHqWx3zVLg6dm0Cgup6mM9JkjY1e"
    encoded .= "eWqS9oui8qbHP//UL7ztbXINePkJvqeXIQB4qkAAAN/y6it/br2Wv6+9HSj0r6/l1J0CYKMz5n6kCswirdsUx5a3XVdnEwkUDanlT9K0btprMJozUD5fMBcQ"
    encoded .= "uxVFsIRAZMsrVsvRJbQBPkERLKGJtCpLIdfnKKhpjbvVExglhJx8wUCt0vLQNqRknSF1mmZ7wTP7nu9d9PgJEfOcR3+Sptmug0hFQg9vbpLPOhhw+LSiV7Td"
    encoded .= "Rk+0sxoEDeJXoCpEtAHQ3psCqxX20NppCBSbfuWKiv5qa/hvk5z9hTe/X37Xax+C/9I5+Z4rvYwBwNMAAmD4C/zpd7zm8C/Nql8uXb4Kgi9T4C9McnrP3YVp"
    encoded .= "zs/ovQezgZg3MsYDjXIW30baaiFg/v8OU7WYxFGfgnksjc+dY06gWmjLRbYhr1vgFV0xJ0/WsxTqrS6o0656NTySLzUu2w1L68E7lk/4sg8W3jTHs6zfoiTp"
    encoded .= "ZVygyagjWrbBBsAtesZGTG4FS3kevGHr+nGsrAEyobWVwQEw92Nov3qoio+hyXvaJO9uOr/nLR+467e9Zxeg7eEDyMtZ8D19FgBAJoXKfecfmi5fvm9mwh78"
    encoded .= "rd/bv3N1918E9r4Q6Peq4K82aV+gXV/VpN3ZVe/Urqcx3smq2mL7vZnYiwmS2krCojh1XKI7Xso7HO1qKs69f2zzmtAKsbodlukel2qQ4UtSl0xo2QNWKNCa"
    encoded .= "tRMGSEiljhvDRFRVhYUvwUJM2QZHey+7auTwUuSZsFfZq7YmIqrm4PbUAFWvwQwKVUGzKAFVO+spMRCB2IrJiDBs62ZWkQJ2aNgW5ioQkaYOhKb5Raw/cDKj"
    encoded .= "mX+YAhDHQJp3QWJrJ+BAJQnp24EK2CnR0b/egENgehroT6HJJ5v2T3bgkblPD0/r6aOPnnvPx+vVXCrnzz803Xf5vv5S7Oc/3/RZBQCcHGWBahls5btX9377"
    encoded .= "FX9yx3pandJrMq0adF6f6dPxlbbpo/zcIfv7wOEhcGp1pgNXovy1SXXVoJsOWbU7dNOfkVOziJddtTN6BVdwJkqcwaZfEf8MXMFRg07XBnfNp0TOWO5NvyJz"
    encoded .= "h0wNWvJ0kb1TkNna2HSRVas2wHQNergP4BDYB4B94NC/PAT2To2yR9eg+/vA3A/lqO3rdA06r7SfAfCUjWmvPyZH7YyOtiBnABxtpG1OQVbXhuRMjXXwFVxr"
    encoded .= "+0aXKwKMEc39UOZ+RvY6ZHPqqvTj0907NLV9vWZjONUlxja10R9ve7WJl3KXNucO2euQKzjEqu3r+AysGnRqWNR9KMA+Nv1QzmAfmy4CHOKonVZY+dHeoYzP"
    encoded .= "QTlca6pnjk/P86njq4/eec8zzxaZd3CgEwDcewn62ST0nD5rAaAmlQsXIA8/DHn0UcirXgX9bJ6Uk/TySq5sKm9BX+7m/Y2kPyUA8Gwp/djXS/fjfgHuH59w"
    encoded .= "/y2Z1FFnfN5Z564899OcPLyYn3sB9X7uqu0G+7VjE3I7XXiW/j9beS63LC878l1c1K0YNLg4xqnL/LvSsg5rVS48Sz8vArhAn3Hdef/sF/JnS38GAOB2JnbB"
    encoded .= "3co6PZWNPt2dZ/ndn4a0pMFJul3pBABeULodAPBsbS3T7Wz7xRzb9drndAIEtyO95KHAL790QxaypZeKKV+Mdk8E7iT9mUt80vwkvfTpZD5ud1q91B04SSfp"
    encoded .= "+unECjlJJ+kknaSTdJJO0kk6SSfpJJ2kk3SSTtJJOkkn6SSdpBeU/j+JMYLM7Zq9dgAAAABJRU5ErkJggg=="
    size := 0
    if !DllCall("Crypt32\CryptStringToBinaryW","Str",encoded,"UInt",0,"UInt",1,
        "Ptr",0,"UInt*",&size,"Ptr",0,"Ptr",0)
        throw Error("Не удалось прочитать иконку ZoomFlow.")
    bytes := Buffer(size)
    if !DllCall("Crypt32\CryptStringToBinaryW","Str",encoded,"UInt",0,"UInt",1,
        "Ptr",bytes,"UInt*",&size,"Ptr",0,"Ptr",0)
        throw Error("Не удалось декодировать иконку ZoomFlow.")
    file := FileOpen(target,"w")
    file.RawWrite(bytes,size)
    file.Close()
    return target
}


; Text and its solid background are painted together, without WM_SETTEXT
; invalidating the parent picture. Unchanged values do not request repaint.
class BufferedLabel
{
    __New(options, caption, background, color)
    {
        global SettingsUI, BufferedText
        this.Caption := caption
        this.Background := background
        this.Color := color
        this.Control := SettingsUI.AddText(options " +0xD Background" background, "")
        BufferedText[this.Hwnd] := this
    }
    Hwnd {
        get => this.Control.Hwnd
    }
    Text {
        get => this.Caption
        set {
            if value = this.Caption
                return
            this.Caption := value
            global TextLayouts
            if TextLayouts.Has(this.Hwnd)
                FitLabel(TextLayouts[this.Hwnd])
            this.Redraw()
        }
    }
    Visible {
        get => this.Control.Visible
        set => this.Control.Visible := value
    }
    SetFont(options, fontName:="")
    {
        if RegExMatch(options, "i)(?:^|\s)c([0-9a-f]{6})(?=\s|$)", &match)
            this.Color := match[1]
        fontOptions := Trim(RegExReplace(options, "i)(?:^|\s)c[0-9a-f]{6}(?=\s|$)", ""))
        if fontOptions != "" || fontName != ""
            this.Control.SetFont(fontOptions, fontName)
        this.Redraw()
    }
    Redraw()
    {
        DllCall("InvalidateRect","Ptr",this.Hwnd,"Ptr",0,"Int",false)
    }
}

DrawBufferedLabel(label, item, offset)
{
    target := NumGet(item,offset+A_PtrSize,"Ptr")
    rectOffset := offset+2*A_PtrSize
    width := NumGet(item,rectOffset+8,"Int")-NumGet(item,rectOffset,"Int")
    height := NumGet(item,rectOffset+12,"Int")-NumGet(item,rectOffset+4,"Int")
    if width < 1 || height < 1
        return true
    dc := DllCall("CreateCompatibleDC","Ptr",target,"Ptr")
    bitmap := DllCall("CreateCompatibleBitmap","Ptr",target,"Int",width,"Int",height,"Ptr")
    if !dc || !bitmap {
        if dc
            DllCall("DeleteDC","Ptr",dc)
        if bitmap
            DllCall("DeleteObject","Ptr",bitmap)
        return false
    }
    oldBitmap := DllCall("SelectObject","Ptr",dc,"Ptr",bitmap,"Ptr")
    font := SendMessage(0x31,0,0,label.Hwnd)
    oldFont := DllCall("SelectObject","Ptr",dc,"Ptr",font,"Ptr")
    try {
        bounds := Buffer(16,0)
        NumPut("Int",width,"Int",height,bounds,8)
        brush := DllCall("CreateSolidBrush","UInt",ColorRef(label.Background),"Ptr")
        DllCall("FillRect","Ptr",dc,"Ptr",bounds,"Ptr",brush)
        DllCall("DeleteObject","Ptr",brush)
        DllCall("SetBkMode","Ptr",dc,"Int",1)
        DllCall("SetTextColor","Ptr",dc,"UInt",ColorRef(label.Color))
        DllCall("DrawTextW","Ptr",dc,"Str",label.Caption,"Int",-1,"Ptr",bounds,"UInt",0x810)
        DllCall("BitBlt","Ptr",target,"Int",0,"Int",0,"Int",width,"Int",height,
            "Ptr",dc,"Int",0,"Int",0,"UInt",0xCC0020)
    } finally {
        DllCall("SelectObject","Ptr",dc,"Ptr",oldFont)
        DllCall("SelectObject","Ptr",dc,"Ptr",oldBitmap)
        DllCall("DeleteObject","Ptr",bitmap)
        DllCall("DeleteDC","Ptr",dc)
    }
    return true
}


DrawPausePanel(item,offset)
{
    global Enabled
    target := NumGet(item,offset+A_PtrSize,"Ptr")
    rectOffset := offset+2*A_PtrSize
    width := NumGet(item,rectOffset+8,"Int")-NumGet(item,rectOffset,"Int")
    height := NumGet(item,rectOffset+12,"Int")-NumGet(item,rectOffset+4,"Int")
    if width < 1 || height < 1
        return true
    dc := DllCall("CreateCompatibleDC","Ptr",target,"Ptr")
    frame := DllCall("CreateCompatibleBitmap","Ptr",target,"Int",width,"Int",height,"Ptr")
    if !dc || !frame {
        if dc
            DllCall("DeleteDC","Ptr",dc)
        if frame
            DllCall("DeleteObject","Ptr",frame)
        return false
    }
    old := DllCall("SelectObject","Ptr",dc,"Ptr",frame,"Ptr")
    try {
        bounds := Buffer(16,0)
        NumPut("Int",width,"Int",height,bounds,8)
        brush := DllCall("CreateSolidBrush","UInt",0xFFFFFF,"Ptr")
        DllCall("FillRect","Ptr",dc,"Ptr",bounds,"Ptr",brush)
        DllCall("DeleteObject","Ptr",brush)
        SmoothRound(dc,0,0,width,height,20*A_ScreenDPI/96,Enabled ? "F4F0FF" : "FFF4DB")
        DllCall("BitBlt","Ptr",target,"Int",0,"Int",0,"Int",width,"Int",height,
            "Ptr",dc,"Int",0,"Int",0,"UInt",0xCC0020)
    } finally {
        DllCall("SelectObject","Ptr",dc,"Ptr",old)
        DllCall("DeleteObject","Ptr",frame)
        DllCall("DeleteDC","Ptr",dc)
    }
    return true
}
