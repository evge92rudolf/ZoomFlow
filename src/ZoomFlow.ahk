#Requires AutoHotkey v2.0
#SingleInstance Force
; ZoomFlow 1.9.1 — Windows / AutoHotkey v2
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
    SettingsUI.AddPicture("x0 y0 w1120 h700", BackgroundFile())
    C["BrandIcon"] := SettingsUI.AddText("x26 y184 w40 h48 +0xD", "")
    TextAt("ZoomFlow", 72, 190, 114, 24, 14, "262234", true)
    C["AuthorLink"] := SettingsUI.AddLink("x72 y215 w116 h22 BackgroundFFFFFF", '<a href="https://www.instagram.com/ruwolfdesign/">by Ruwolf Design</a>')
    C["AuthorLink"].SetFont("s8 c82798E", "Segoe UI")
    C["AuthorLink"].OnEvent("Click", OpenAuthorLink)
    names := ["Зум", "Управление", "Плавность", "Программа"]
    for i, name in names {
        C["Nav" i] := ButtonAt(name, 30, 240 + (i-1)*54, 150, 42, "nav" i)
        C["Nav" i].OnEvent("Click", SwitchPage.Bind(i))
    }
    C["PauseCard"] := SettingsUI.AddText("x30 y512 w150 h144 +0xD", "")
    C["State"] := SettingsUI.AddText("x44 y528 w124 h24 +0xD", "")
    C["State"].SetFont("s11 Bold", "Segoe UI")
    C["PauseDescription"] := BufferedLabel("x44 y564 w124 h34", "Управляй масштабом`nдвижением мыши.", "F4F0FF", "7B708E")
    C["PauseDescription"].SetFont("s9", "Segoe UI")
    C["Pause"] := ButtonAt("Пауза", 42, 606, 126, 36, "status")
    C["Pause"].OnEvent("Click", ToggleEnabled)
    TextAt("ZoomFlow", 32, 40, 252, 48, 32, "FFFFFF", true)
    TextAt("Масштаб под твоим`nконтролем", 32, 88, 240, 48, 16, "D7CAFF")

    PageIndex := 1
    TextAt("Настрой свой темп", 248, 192, 500, 30, 18, "262234", true)
    TextAt("Выбери пресет или отрегулируй зум вручную.", 248, 230, 500, 22, 10, "82798E")
    for i, label in ["Точный", "Обычный", "Быстрый"] {
        speeds := [60, 100, 160]
        speed := speeds[i]
        ButtonAt(label, 248+(i-1)*172, 268, 156, 40).OnEvent("Click", Preset.Bind(speed))
    }
    C["SpeedLabel"] := TextAt("",248,316,500,24,11,"262234",true)
    C["Speed"] := ControlAt("Slider","x248 y340 w500 h28 Range25-300 ToolTip NoTicks",Cfg["Speed"])
    C["AccelerationLabel"] := TextAt("",248,374,500,24,11,"262234",true)
    C["Acceleration"] := ControlAt("Slider","x248 y400 w500 h28 Range0-100 ToolTip NoTicks",Cfg["Acceleration"])
    C["GainLabel"] := TextAt("",248,430,280,20,10,"82798E")
    C["MaxGain"] := ControlAt("Slider","x548 y426 w200 h28 Range10-40 NoTicks",Cfg["MaxGain"])
    C["GainHint"] := TextAt("",248,454,500,36,9,"82798E")
    TextAt("Интервал обновления зума · мс",248,506,412,20,10,"82798E")
    C["Interval"] := ControlAt("DropDownList","x680 y538 w68",["10","15","20","30"])
    chosen := 1
    for i,n in [10,15,20,30] {
        if n = Cfg["Interval"]
            chosen := i
    }
    C["Interval"].Choose(chosen)
    TextAt("Как часто меняется масштаб при движении мыши.`n10 мс — чаще, 30 мс — реже. Начни с 10 мс.",248,532,412,36,9,"82798E")

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
    C["TestPanel"] := SettingsUI.AddText("x800 y172 w296 h500 +0xD", "")
    TextAt("Проверить зум",824,192,248,30,17,"262234",true)
    C["TestHint"] := TextAt("",824,235,248,66,9,"82798E")
    C["Canvas"] := SettingsUI.AddText("x824 y312 w248 h224 +0xD", "")
    ; Keep the existing font/value handle; render the badge inside the canvas bitmap.
    C["TestPercent"] := SettingsUI.AddText("x836 y488 w80 h34 +0xD Hidden", "")
    C["TestPercent"].SetFont("s17 c6344D7 Bold", "Segoe UI")
    TextAt("Сетка и фигура — тестовый холст.",824,548,248,20,9,"82798E")
    ButtonAt("Сбросить масштаб",824,608,248,40).OnEvent("Click",ResetTest)
    ButtonAt("Применить и сохранить",248,608,226,40,"primary").OnEvent("Click",SaveSettings)
    ButtonAt("Скрыть",492,608,118,40).OnEvent("Click",HideSettings)
    ButtonAt("Помощь",628,608,120,40).OnEvent("Click",ShowHelp)
    C["Notice"] := TextAt("",248,650,500,18,8,"82798E")
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

OpenAuthorLink(*)
{
    Run "https://www.instagram.com/ruwolfdesign/"
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
        ctrl := BufferedLabel(options, text, "FFFFFF", color)
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
    ButtonKinds[ctrl.Hwnd] := {Kind:kind, OnCard:true}
    DllCall("UxTheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "", "Str", "")
    ; BM_SETSTYLE replaces the button type instead of mixing style bits.
    DllCall("SendMessageW", "Ptr", ctrl.Hwnd, "UInt", 0xF4, "UPtr", 0xB, "Ptr", true, "Ptr")
    return ctrl
}

SwitchPage(index,*)
{
    global Pages, CurrentPage, C, SettingsUI
    static initialized := false
    if !Pages.Has(index) || (initialized && index = CurrentPage)
        return
    previousCritical := A_IsCritical
    Critical "On"
    try {
        EndSliderDrag()
        changes := []
        for number, controls in Pages {
            show := number = index
            for ctrl in controls {
                visible := !!(DllCall("GetWindowLongW", "Ptr", ctrl.Hwnd, "Int", -16, "UInt") & 0x10000000)
                if visible != show
                    changes.Push({Hwnd:ctrl.Hwnd, Flags:0x001F | (show ? 0x0040 : 0x0080)})
            }
        }
        ; SWP_NOREDRAW + a deferred batch: change visibility without intermediate paints.
        ; No WM_SETREDRAW on the GUI and no change to its drawing order or styles.
        batch := changes.Length ? DllCall("BeginDeferWindowPos", "Int", changes.Length, "Ptr") : 0
        for change in changes {
            if !batch
                break
            batch := DllCall("DeferWindowPos", "Ptr", batch, "Ptr", change.Hwnd,
                "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0,
                "UInt", change.Flags, "Ptr")
        }
        applied := batch && DllCall("EndDeferWindowPos", "Ptr", batch, "Int")
        if !applied {
            ; Recover safely if Windows cannot allocate the deferred batch.
            for change in changes
                DllCall("SetWindowPos", "Ptr", change.Hwnd, "Ptr", 0,
                    "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", change.Flags, "Int")
        }
        CurrentPage := index
        initialized := true
        titles := ["Зум", "Управление", "Плавность", "Программа"]
        SettingsUI.Title := "ZoomFlow 1.9.1 — " . titles[index]
        ; Repaint the settings card only, without clearing the entire window.
        scale := A_ScreenDPI / 96
        rect := Buffer(16, 0)
        NumPut "Int", Round(220*scale), rect, 0
        NumPut "Int", Round(172*scale), rect, 4
        NumPut "Int", Round(776*scale), rect, 8
        NumPut "Int", Round(590*scale), rect, 12
        DllCall("RedrawWindow", "Ptr", SettingsUI.Hwnd, "Ptr", rect.Ptr,
            "Ptr", 0, "UInt", 0x0181)
        Loop 4
            DllCall("RedrawWindow", "Ptr", C["Nav" A_Index].Hwnd,
                "Ptr", 0, "Ptr", 0, "UInt", 0x0101)
    } finally {
        Critical previousCritical
    }
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
        if !isState {
            brush := DllCall("CreateSolidBrush", "UInt", ColorRef("F6F3FC"), "Ptr")
            DllCall("FillRect", "Ptr", memory, "Ptr", bounds, "Ptr", brush)
            DllCall("DeleteObject", "Ptr", brush)
            SmoothRound(memory,0,0,width,height,10*A_ScreenDPI/96,"FFFFFF")
        }
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
        ? "Ограничивает разгон при быстром движении мыши.`nДоступен, когда ускорение больше нуля."
        : "При быстром движении зум ускорится максимум в "
            . Format("{:.1f}", C["MaxGain"].Value / 10) . " раза.`nНапример, 2× — до двух раз быстрее обычного зума."
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
    target := ConfigDir "\appearance-1.9.0.png"
    encoded := ""
    encoded .= "iVBORw0KGgoAAAANSUhEUgAACMAAAAV4CAIAAADD3KSqAABfW0lEQVR42uzdP5IVS9I36AK7YzajI7EABITeAqtpAYHVtHAFVnO3gIDAApBahjFGGaHso8uL"
    encoded .= "qlPnj3ume8bzGPbafRsqKiI8Ms7J/J3M8+rnj193AAAAAAAA8H+8NgUAAAAAAAA8JEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAA"
    encoded .= "AAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAA"
    encoded .= "gECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAg"
    encoded .= "ECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAADBX8ce3scPX9QYAAAAAAA29v7d23P+2ddv3zt3+MXu/f3Pv45awVc/f/w60ngk"
    encoded .= "RgAAAACwpusu/oK1tNkcPmf3uX2xt+f38Eh50hECJKERAAAAAKws8eLvXr1tGE6s2U9raZtDsk+3S4Ou6WHS7ABJdAQAAABwwqPrYm0/Pj+ln2rUs5+DHpM1"
    encoded .= "JZxYtp/W0paHZHq9rhhyadD1u/FPn98MfYUaGSDJjQAAALjOyhdqp7RJ0SpqW6kp/axY83Vjn9LP0vXTsM/V4URW3aeEKLn9tJay1tLV6VFWva4IeCo6+WTj"
    encoded .= "45KkYQGS6AgAAOjMxfRB1UmsVP8LtVPadLxvsNpb9XnWl6vnrvm6sU/p58arqENvSx+TlVj3Kd9bk95PayllLd2YHp3zi7L2pdKg63Tjg2KkMQGS6AgAAOjM"
    encoded .= "xfTm4VnRY17S617RzyltOt43W+1NOrxBPxP3pdw1Xzf2Kf3cZRXt29ttHpO1QVNzS5+SSVhLRdN4/i9K3JfqAqQzWx4RI70e8c5MegQAwMO34w//tG2T1ZZl"
    encoded .= "3dnpiPX5Z8dSupo19nN+9or20+te0c8pbTre6bwvTVnzqx2b1a8Lu3f1zJ9KrHtpPzvPp7W04B5y+0Cea+H8lv/z7//2n6juAdLHD1+kRwBwpHM8V+fNZ/rb"
    encoded .= "9Iq3/lapNZ9+/pl41TI9N62bgduTs5QGz/+pi9pPr3tFP6f8y9EvQ90GXhEHTuxn4r6UvuaLxj6ln+x1KCkQB1hLx9uX/vPv/zaPkVoHSKIjgD5vI0ZcpNbP"
    encoded .= "zv181FTFjSMLHpUV8zn0rKbiM4POsa35o6759PksuhvDsQl025cYVOVtWtjgF225XJftp7XU56jcrMOJlyNSWu6cIfUNkKRHAA3fl3c+1yrqZ3o4sfh8LttP"
    encoded .= "NniXX3FfgkVF7vln7kcmm6zP/o+GW/mT/lPadLzv0sN9ezvoEUzpa75o7FP6yb6HkgIxei0de19qmyF1DJA8tg44zAvqIYfccxLqvnehrsGl5rP5o40Osxc5"
    encoded .= "IcSax3wCAMBE//n3fxvGIu0CJNER0Nb9VRXXVgAAAACAdN3ykddmB+BMX799//1/AQAAAABytUpJXpsXgPMtmB79OeSek1DUz4eNpDe41Hw+9+PpzS5ykBbN"
    encoded .= "J1jz5tPkAADA7vpkJa/NCACnpYcos/r59dv3+z/mUz9pVe5L/3bLNrEys1bUiPV5Tjeu6Gri2HOnva7uFf2c0qbjfZce7tvb0n7mruT0NV809in9ZN9DSYEY"
    encoded .= "vZZW25eaJCavzQUA57zc5oYo+rlgPx81ld7yaudCdfM59MTmluG7G8OaX23Np89nUdDl2AS67UsMqvI2LWzwi7Zcrsv201rqc1Ru1uHEyxGlNeqQm+wfIEmP"
    encoded .= "AGCp07wFwx7zWf1ev+KUzyq15tNPQRNzlIYBfPNHlRbdapBe94p+TvmXo1+Gug18yh0J1f1M3JdG3HE4qJ/sdSgpEAdYSwvuS7unJ69+/vi1+BQAAADc7v27"
    encoded .= "twc+d71iBrqN+kSBbulwet0r+jmlTcf7Zqu9SYc36GfivpS75uvGPqWfu6yifXt7RVfP72Ri3Uv72Xk+raWUtXT1NJ7/ixL3pRt7e6Lx3Br9/c+/dnxTsXOA"
    encoded .= "JD0CAACOpHmIojpXnLRvX/eKfk5p0/G+wWpv1ecp/axY83Vjn9LPjVdRh96WBnKJdV82hLaWUtZSSoaUEvy82Nu6ACm9RjtmSHsGSNIjAAAANjYl5Kvo55Q2"
    encoded .= "KVpFbSs1K4zsHxjP6mfp+mnY5+pALqvua4bQ1lLWWioNZnL3pdI7z3JrtFeGtFuAJD0CAAAAqLZyaKpG6/Rz0N1sUx4Bumw/raUtD8n0etXdZ3ndb8mt0S4Z"
    encoded .= "kgAJAAAAAJht1nezPdnb/rfcLdJPa2mbQ7JPt6sf25hVo4UCJOkRAAAAAJBrSuCBtbTsHD6n/xMRO1R/+wxphwBJegQAAAAAAMc26JGAJzrcKjjcOEP6yyIG"
    encoded .= "AAAAAABy/Y5eptzR5SazR7a+A8ntRwAAAAAAAFfY8iYkdyABAAAAAABVptyBVNHP0d+ntekdSG4/AgAAAABY1uiL6Q3H3nw+p3wHUkU/S8e+2U1IAiQAAAAA"
    encoded .= "AGq9eD39wDFSxdj7z+eZCcruva3oZ/XYBUgAAAAAAOwm6+6WKUHCZnN449ir5zOl7hd1MvFXdOjnBmM/YIAkPQIAAICDeXSJZJFnEBn7ymOfMp/WZ/+xN697"
    encoded .= "4t0tG1xMb1v3ceFEVt2v6GRu+zv2s3rsv22TIQmQAAAAaMpF6kHVSaxU/7rPGntum3Vjdxxlzaf12X999q974ne3bHAxvW3dx4UTWXW/upO57e/Sz+qxP/wt"
    encoded .= "nz6/2WAZbxQgSY8AAACOzUXqZWudWKn+dZ819rYXlIfuS/3XkvXZf32OqHvi49GmBAk71vqiPpfOZ1bdb+xkbvsb97N67H/+ig0ypNfe+AIAwPt3bx/+MSFw"
    encoded .= "xRF0zv94foNX/y0blDv9X06p+6yx57ZZN/Yp+1L/tWR99l+fI+peN/mD9mQv7lf/+6ypzmp/y35Wj32vlSxAAgDY4u24cGLW+ZIyQcpZ7nVH0zk/0u0grdjn"
    encoded .= "V3vtmFj3zmNfeT7vhNDWJ5XlPv+nbi/i3GVQMfa6+ayIgfuvT84kQAIA2PptrrewKbOadUW1+lNpWJ/H7mf6RcCJnybe5hLPuNsmLvr3I+o+aOwr35FwNyGc"
    encoded .= "6BC3WJ/qfryTrHXGjgsLW9oiQPIFSAAw9N3JOhdAt3+Tl5V8LHhL06Mh3zgDPqFM5/Wpn6NP5iu2JmUCYPtXtOt+doPHeR1yJp9rp24+E+ueW6zExjfoZ+nY"
    encoded .= "T/jPv/9bvZ7dgQRwwPd8y14Gqhj7svNZ8VZ1wX6WhhNTajT91M7cQsoBcsi7HO4mfC/IXhW/6KdG1H3Q2NPbnPXIoP53s/XZGaxPdV/hHYg39qz2rjudAAng"
    encoded .= "sK8oC96UkD72ZedzyiPXVn403LJj96l8rE/HEQAAsA0BEgAAAAAAAIEACQAAAAAAgKA8QPr44YtZBtjM12/fn/xvYzefVw+88/Cn9NPYSwe+5o6H9ek4AgAA"
    encoded .= "/vPv/5a27w4kgKP5+u37/R9jN583DvzJ/9bPq7t36d8epkZT1nlRmcBBdNG/vPSI2/0IrdjnS187Nqv4RT81ou6Dxp7eZtHYp+xLI9aS9dl/fQ6q+8HegXhj"
    encoded .= "z2rvutMJkACAZ9+gjAjPmvez9JP+awacj4Z84wx0vlCL9amfo8/nK7YmZQJg+1e063624rkgK8zkc+3UzWdi3dM/zjuon6Vj35cACQBg6/MHVwBTZjXrkrcL"
    encoded .= "tXRen/37mf558/53D2yzz7d97Si6W2hE3QeNffG7A/vfYTzizh7rc+W6Dz3JWmfsuLCwJQESAMAWb/Ue/jEh/d+LKxNknc1ecTRNfLxkxT6/2mvHyo8V3esy"
    encoded .= "8YHXlTuMrU/qyn3+T1V8nOLYM1l9hpJbqWM8CpIXCZAAAEDIBwlH0Dn/Y8qpvoN093Kn/8spdZ819tw2x90dmL4v9V9L1mf/9emOril7shf3q/999aMLO/dz"
    encoded .= "g8c27rKSX/388av0F3z88MURCAAAwBXev3u7+2kzZ1YnsVL96z5r7Llt1o3dcZQ1n9Zn//XZv+4nWru05TObuqXbbeteMfbS+cyq+9WdzG1/l35Wj/3J3/Lp"
    encoded .= "85u6ZSxAAgAAAK60cshn7GuOfcp8Wp/9x9687i9eB08JeG5vvHndK8ZeOp9Zda8ODjv3c4PQ9NEvEiABAAAAALCpJy+F193SdHX74+bwxrFXz2dK3TcIDtv2"
    encoded .= "c5vQ9Le///lX3QIWIAEAAAAAUCvxriZjHzGfU4LDiSHfQwIkAAAAAADGy7qrydhHzGfi92mN6+dmYxcgAQAAAAAAI00JDieGfKUB0l/WLgAAAAAAUGTKTWYV"
    encoded .= "/Rx9g91raxcAAAAAAICH3IEEAAAAADDbgt+vg7qrezUBEgAAAACwtZUvfOf288Sl5Pu/uqLlijZn1Ujd+9d9zT1ks+jo3qufP36V/oKPH754OQQAAACAuTa7"
    encoded .= "8H11yxVtbjaTV/fzokvJZ7Zc0easGvVf8+q+5h7yXA8/fX5T90t9BxIAAAAA8LT3794+d9XyxF+dbjDl31S3WTSZif3sMEu5ve1Qo/5rXt3X3EP2+u3uQAIA"
    encoded .= "AACu9Ohyhi9IMJ8ce00+p+IWhzNbrmiz4thM7+fVV5NPNFvR5qAajVjzi9d92T3kdCdL70DyHUgAAADLcZFajdJ7+PB/tKJazeeU492+1HA+L7rJ4Kgl67nX"
    encoded .= "3XIvwnPFqmhzXI2ar3l1X3MP2ffOJ3cgAQAATufu7tb+9uaVZ2BKMNOtt7O+x6L/WiqazynHu32p53yufOdE+rGZ3s8bLyinBwkVXd24RiPW/OJ1X3YPebGR"
    encoded .= "0juQBEgAAFufxrsUgjXfsJNZXW0+dhf9i+q+Wo1yH+8zdF9KXEtF8znleLcv9ZzPlS98px+b6f1MuR3hUbMVbQ6q0Yg1v3jdl91DzmmkNEB67ZUVAODPt2jX"
    encoded .= "fTnqmW/4mnw3rBrpZ92o+6/5E1+MfOCxD/ry6ll1X61Gdd/yPWhfSlxLRfM55Xi3L5nP0ZNpStUIDr8+BUgAwKZvoZpfTH/Uvdt7W3qxctlwIrdGi/dzszOl"
    encoded .= "QTnK1V0dMXan8UNP3Wm1L1lLLL5hXvGztx8XFR/R2OZoTe9nxafcij45N6VGI9b84nVfdg/p8KZCgASw8/vyBS/+qpET0btlrq2UXmBacD5ZfM1veRqWfg/B"
    encoded .= "lI/5H3hLcWfP9p0cMatFNwzVlfLMfz/leHf3gPk8wGSaUjWCY69PARLAbhu6i7+zKq5G6YfPOo+0WnY+V66RO1EAAACYToAEcK77q36u/QEAAAAAhydAAjjX"
    encoded .= "12/ff/9fAAAAAIADEyABXCA3PXrYmlyqf8XVKP3waTilz3VpRFcXWaJTajRoLQEAAMCTBEgAe/r67fv9H1OhRotM5pP/vciQL/1b84k1v0snr+5q/7Gf34dD"
    encoded .= "bilFdV+wRpf+6uazmn6wV5fyzH8/5XhffF8yn8eYTFOqRnDs9SlAAgA2fRfVPJB71L3be1t6J8qaAWd6jRbv52YnS62GXxT2uPNs9Jm8MtmXrCVIWcZP/uzt"
    encoded .= "x0XF/ffbHK3p/czqdsXH0dK7utmO2n/NL173ZfeQDm8qBEgAAE+8S0u83L/s4+YG1Ug/q89z1nlkZfOxj7gLZ2LdV6vRxLsc0o/NxLVUNJ9Tjnf7kvkcPZmm"
    encoded .= "VI3g8Ovz1c8fv0p/wccPXywXAACgoffv3g46eSsatRloOOoRNTrRyXWWU+JaKprPKce7fannfL64LC9t/4oGX2y2os2KYzO9n1c3eKLZijYH1WjEml+87svu"
    encoded .= "IS828unzm7rXFAESAADActYMz9SotIdWVNv5nHK825cazudFl1ZTLoNe0WxFmxXHZm4/BwUJg2rUf82r+5p7yL4B0l9eUAEAAFbjyqwaZfXQRf/+8zmlKBZP"
    encoded .= "w/n8+u37mZdWD1y+nnvd+aU5v1gVbY6rUfM1r+5r7iG31Oh27kACAAAAAJ6W/ojFigv0U4Ku3H7OuhtjUBjZfM2r+5p7yIkelt6B9NqrIAAAAADwpK/fvp+4"
    encoded .= "d+GKy6nn/MilzVa0WTSZif3sMEu5vW1yR0vzNa/ua+4he/12dyABAAAAAFt78gP1uV/6ldJm/7Gn3zFT1OasGql7/7qvuYf82cPSO5AESAAAAAAAs60cyKm7"
    encoded .= "uq9cdwESAAAAAAAAwd///Kuucd+BBAAAAAAAQCBAAgAAAAAAIPjLFAAAAAAAwDi+r2jNGj3ZZgUBEgAAAAAAjwknxlXn4V+p1CFrtFl0dE+ABAAAAMCeXKRW"
    encoded .= "9851X3N9zgonNrvDo8moz4wQDh8jrVajjaOje69+/vhV+gs+fvji5RAAAACAP714OUyMpO762XDgNw7/Ufu3TGNFjUrrfvvYr0gRbv8t3Zb6gjU60eanz2/q"
    encoded .= "plqABAAAADepuMjS/MIN1nzK+qy+SG0P6TmHU+o+KERJbLM6nDjRfl1vs3pY19vzW7v6HpSUX5F7U1fD1462NTrdpgAJAABYnYvp6n4357lGN/a27sKNuht7"
    encoded .= "qzV/0SW266aifzCz4B6yQd3797Nz3esCpPSL/hU1Kqp71thvfIJZVvt7BTPL1ujFNgVIAADAulxMH1qphhdVt1ycV3d18cd5zTrerflbujrrLoeiNhfcQ7Z5"
    encoded .= "9Fbzfnaue93dLekX/Td+RNhmXT3dYGmAVBea9n/taF4jARIAAIc15VPk7m6ZsoRuPH3doO7LrqXcLzEeUfdZj80ZsX/OOt4HrfnNNuTzu1r9CKYRwcyCe8gG"
    encoded .= "j97q38/OdR8UTmz/iLDNelvRw4r2t7+zZ9kandNmaYD02hkpAACbnX6nvKW+b+f+T/N+Fs1q4tjHLaHE87SKus9aSxtU6rrhj6j7+T+1778ctM/POt4Hrfkt"
    encoded .= "N+RBXb20k+lt2kO8N16q7hVH3PGKvu/Yi/ppfR6AAAkA4Il3hOtcoN/+jfjt1+wetnB7pYr6WbcyE8dufebWfdBa2vKsu9Xwl63R4vOZ3s9Ba37iplH3s6i7"
    encoded .= "9Vna+c2G3+3d2jYDr/vknD2kc4061EuABHDA9+XplxSnXEx30X/N9Vn6ts9yKnr33Pmz84e5CnD4VXRLpSrqvuxaGvGp/PQa7X7vwl37mzzqhrP78T5oze+y"
    encoded .= "IQ/q6o7/0h7ijc1Sda++0/dIRd9r7EX9tD6PQYAEcNi3pEf97MP0flqfzWu07OOnpp+DrVAmd04AAACwJQESAAAAAAAAgQAJAAAAAACAQIAEcChfv31/8r+7"
    encoded .= "tTll7CxYoz87Zjk1L9A6ZVp57AAAAGxPgARwNF+/fb//07zNKWNnwRoJI9On8dK/1U8unf9LK1VR92XX0jlDu2j4I+qe+6vr2hy0fw463get+V025EFd3fFf"
    encoded .= "2kO8sVmq7hXvrI5a9L3GXtRP6/MYBEgAAE+8HRRG1r0Xv3FiH5Xm9koNurMnfezWZ27dl71LbFB45k6+NeczvZ8+fFC6adT9LOpufZZ2frPhd3u3ts3AK54x"
    encoded .= "Yw/pX6MO9RIgAQCw3XvoxHfVifHJrEcXLhVwVnz2trTuyz4GM/dyzIi6j7jLYdY+P+t4H7Tmt9yQB3V193tB7CHeGy9V95XvkJsy9qJ+Wp8H8Ornj1+lv+Dj"
    encoded .= "hy9eHgAAgKu9f/fW+dvESt1YnRF1P9HJq7ta0abj3ZpvuOZfbOrGeaiYz/Q2F9xDqus+op+d637FwM9s/6KWz+ltRY2K6p449qsLlN541obc5LWjeY1ebPPT"
    encoded .= "5zd1+6EACQAAGCD3Qi3qXtTDlN4KTVc+3pda83UXK0vns39w2HwP2aDu/fvZue514dmZLRdlCRURWnpXKyKuivZzM84mrx2dayRAAgAAgMH6X6SGnmu+7mKl"
    encoded .= "PaTzHjKl7tX97Fn3WXcHVtSoeYhSd5dYUY1mvXa0rdHpNgVIAAAAABzQ4o9tVPfmdV92fQ4Kz8Y9CrJ/yJdeo3HHZs8anWhTgAQAAADAYT15XUx0pO762W3U"
    encoded .= "bWegokad6z7lUZArH5tbPmJRgAQAAAAAwKaEu+Oqo1KHr9GfbZYGSH+pIgAAAAAAj0gg+ldHyLdajU60WUGABAAAAAAA88iK1qxRbNMdSAAAAAAAAKOMvktM"
    encoded .= "gAQAAAAAAEzSPJg5/ZS53397XYc9wg4AAAAAAOB/SoOZbTr56F+e39XNcqPfBEgAAAAAAPA/ox87duD5LApmEvt5RcZz/yMv/pbt06O7u7tXP3/8Kv0FHz98"
    encoded .= "cXgAAAAAwDZc+FYj83nLfL54mV6l9prPKxKUxMbPaerGjOfErzjR8qfPb+rKJ0ACAAAA4AKPLmO1vZY6pZ91Q/5Tt0lQo/41al739Pk8MwBoVabOx1HifF6d"
    encoded .= "zSQ2frqplDuEnvwVp1sWIAEAAEBfFRduFryoauwTq9O2UnX9XORC7QZjV6OKGq22h+TOZ+ndLQvudbnzucudPZe2VhQgvdisAAkAAIBMK9890P8C6JQL9BtU"
    encoded .= "fKmxj65Oq0rV9bN54HHRhcvEezJ2v+g/aA8prVH/1/f0uqfP56wAqf9x1D+Yye1n4hcUPWz/nGYFSAAAwCTuHhhUncRKLRjMVDyGaOXHT3ms09Cto+iA6hai"
    encoded .= "FK3Phhdqq8c+rka7HES5wz9keJY+n6WPRxu0J2cdR4nzWRTM5PYzsZMP2z+z2dIA6bX3QAAA8P7d24d/9DP3hLbzlK62Pk//+C2N59a9op/pbZ7zI5c2W9Hm"
    encoded .= "lON93NhZ6rWjaH1m7UsVu+K4Y7N5P0trVPr6PmXHuPGn6t60HG9iq4+1LedT3c8hQAIAnn0/1PxKOmpUd+bQc1ZH9PO5Li21UHOPzREX6HPrPiKYqbiwW32x"
    encoded .= "uPPxPm7sXii3+fd7/d5t1ueIYCZ97LNqdKQjdN+BVx/L9mTHEXUESADwwhujBS/QPxrysjPQ/zaUihotuOanBB4j+rnap183ODbVnXGbp7pjLbWawLqfRY0O"
    encoded .= "M5+3T7Iy1c1n7tzmtvy7hYoF0OesXIAEADu8a0HdjX3E6U2fSRjRT4+fal73KZ+gH3FnT4cH0/X/LHndB5ntJA3LXXo0FR2YZ/7Uyp/0Tx/7rBod7wjda+DV"
    encoded .= "j++zJzuOKCVAAoBz3w8tfj192eGv84gw31sD9k8AAIDfBEgAAAAAAAAEAiQAAAAAAAACARIAPO3rt+8v/i+LDHzx4TcceFGNll3zYP8EAAD4kwAJAJ718JKf"
    encoded .= "y3/qbuyHH/Klf6ufV3TDXrpj3c//9xe1nF73in6m/8uKya8raP/jfdbY7UXbH01FB+aZP1W0PusOkB1Lnz6Z+9boeEfoXgMv3UPsyY4jqgmQAOCFd0X3fxYc"
    encoded .= "9XP/r7ofu0YLrvkpd42M6OeUQG7QsanujNs81R1rqdUE1v0sanSY+bx9kpWpbj5z5za35d8tVCyAPmflAiQA4NT7FW+F1WjNk5yes7ryIxZXPjYT6153l1hu"
    encoded .= "3fe6X+d4d0oNOt7Hjd0L5Tb/fq/fu836HHHn7og7OO0h/deSu1tGzKfXYp4kQAIAgP9d8R9x81nzfvo+rc51r/ukf27dK/qZ3uaIoGvQ8e4xmDa6WUt9g22k"
    encoded .= "+mLu9o8ZnFijLbtXtwaOt3mmz6e7xHKPoynzqe7nePXzx6/SX/DxwxdvgwAAAFp5/+7tiHPgin7mtvmotZSWK9ocujKXGvvo6rSqVF0/69Znyr505sCv+xW5"
    encoded .= "Y59Yoy0XZ+IyaLVzptc9fT4vanD3Ge5/HCXO5xVNlTb+ZFMpnfyz/XOa/fT5Td1KEyABAADATfoHXeaTouq0rVTzsGf7Uaf0uX8Ar0ar7SG58zkrQOp/HOXO"
    encoded .= "543xTG7LGwddLzYrQAIAAACgi5XvYpxVmj91mwQ16l+j5nVPn8+JId8ioenV8Uxi46ebqrtT6nTLAiQAAAAA4CxPXmp0M58amc9bWlOp3OpcN5+ld4ml9HOX"
    encoded .= "O6UESAAAAAAAsBEhX8/5rP4usdv7WXen1HMtC5AAAAAAAIDVjXjMYFHQ9WSzpQHSXxYcAAAAAADQ3++4pfNdYl+/fa8Iuk6PvYIACQAAAAAAmKT5EwVLg674"
    encoded .= "4+5AAgAAAAAAGKUi6HIHEgAAAAAAu6m4c2JKm6y5PicOuZQACQAAAADYmov+46rz8K+uqNSUNh1H/Y/Nurp3ns/t06O7u7tXP3/8Kv0FHz98seECAAAAHMPK"
    encoded .= "F/0FHqUzaVanVOeKSk1pc9bxXnEc9T826+refD5PNPXpc+F3IAmQAAAAAHjZyhf9S8f+qPGUaaxoc7PJvLHPq81nbj+vuMXhxd8ypc1Zx3vFcVR9bG62e1zR"
    encoded .= "2+bzebopARIAAADA9da5+FvX5soX/evGfqLlit7mPoWpSTix8nym9/PqB2Sd+BVT2hx0vI8L5LLWfFHd+8/ni60JkAAAANY15cI3jDiC2h5NzS98lz4qas2x"
    encoded .= "z7p7oPOF75XnM7efN369ypPtT2lz1vE+MUC6fc3X1b35fJ7TlAAJAABgRVM+9bzZDOjnIv3c5iBqNQlzv3dhg8YPOfZZ3weTNZ91d42sOZ/p/RQgjTjex93R"
    encoded .= "lbXmi+refD7PbKo0QHrtlAwAgFnev3v78I9+cuClXnQW/efP9lyi+rlmPzc7iPpMQkU/E9u8booSGz/q2Fc7jnJftsznLh3b/lVmmzYHHe8Vx1H1sZnyb4rq"
    encoded .= "PnE+tydAAgB44n2bK/6DzrqzKpVb9wUv1JK7luouMFWc7m5zsOvnCv3cYMjdJqGin8befOw7RmKX/nvz2Xw+i/pJ8/XptZgtCZAAAMLb1ofvXBeMkZqHZ0UX"
    encoded .= "QNPrvuCFWqbsIXV3NemnfnLUbW2XnzV2C8mUzirQn+1MaXPQ8T7rjq7m63PEfDbZ9wRIABds4iMuJVf0090YsOCpY8ND3oVa1jwYE8+oV36cl3727+deB9G+"
    encoded .= "MzDozglj32vgde8u0p8ZZT43nk+PWDzei9HBauQOuWMQIAFc/DLW/Ps20vs5ZexQ9wZ3kZW/7CPX3C2EtQQAAPAnARIAAAAAAACBAAkAAAAAAIBAgARwlq/f"
    encoded .= "vj/53yv0c8rYIXe1n/O/H374yw7cjoe1BAAAIEACONfXb9/v/yzYzyljB24/2J/874bdu/Rv9ZO5B2PWvzzzH3dYovq5Zj/3Ooj2nYGKfhp787Ff90sr3l28"
    encoded .= "+FPms/l8FvWT5uvTazEbEyABAIT3rI9ClNXexTYPjIvu8EivuztR7CFt9xBBrH7amkhcPHU/a+wWkimdVaA/25nS5qDjveI4GnFsFtW9/3w22fcESAAAT7xp"
    encoded .= "c9fdoPPbxDOKxLov+0hAstZS3V0jUwJO/VyznxsMudskVPTT2JuPfdDdV+az+Xy6w+NIL0aHrNGU1yNOECABADDvPOThH/3kwEu96DR7SsCpn2v2c7ODqM8k"
    encoded .= "7HU5u+gKdXrjRx37aseRO7qa70tT7m6pu2NmxPFecRxVH5sp/6ao7hPnc3uvfv74VfoLPn744sQPAADgau/fve1/bglTjqC2R1NFPxPbPNFUaeMHHvuZzV7U"
    encoded .= "24o2c+fzosm8qP015zO3n1dU58X2p7Q563ivOI7qjs2sNV9X9+bzeU5Tnz6/qXt/IkACAAAADm5KEFvRz6w26y6mrzz25uFZ+nz2v0g9az7T+3n1Nfrcq/O7"
    encoded .= "tDnoeJ8YIKWs+aK695/PF1sTIAEAAACwsxevYR34FsnSsXcOz3aZzBv7vNp85vZzSjhRGniMON5n3XW38e5xRW+bz+fppgRIAAAAALTw5GWsRZ6uufLYN5hJ"
    encoded .= "szqlOldUakqbs473iuOo/7FZV/fm83miKQESAAAAAHAoArlx1bmxUmsGHhOPozXDs/7z+dyoBUgAAAAAAGxqSjghjLQ+F6n7k0MWIAEAAAAAABCSpNIA6S9z"
    encoded .= "DQAAAAAAMEK80UqABAAAAAAAFJvyaLiVH1344rdAZREgAQAAAACwBeHErNL8+bfXTULifE7p5/Y1quA7kAAAAAAAtrPmnRMvXvtuMgNT+pm7li5KJi5qP3c+"
    encoded .= "p/Rzy5VZ+h1IAiQAAAAAjmblRxsxbmUefpXWXfSf1c/cfSlxLV1xX8s5jafP55R+VtT9RCcFSAAAAAB08egyVrfr3WteoKd0fWa1eeZ16qz2p9zQ0+QgLe1n"
    encoded .= "+r6UuJaufira6cbT53NKPyvqfrodARIAAAAran6RGmvJTDac1eoL9HQ+NivWZ1ab1SFK22Oz6KJ/+loq7WfuvpS7lm78Tp3nWk6fzyn9rKj7i+0IkAAAAFhL"
    encoded .= "3YWwlYOEzp/Kt5ZGH5Up85Aynxs8JksY2fPYrFifnS/6b3lsbrBv1M1AXXXO/y2dH+N248Cfazx9Pqf0s6Lu57QjQAIAAJhhzQv01dN46Rn7Fc2ufOl/90/l"
    encoded .= "W0vHOCpvmQR3eHi53LL0FYnC7TcQbNPy9gt1gwApZS3V9bPzY9xSUpknG8+dzyn9rKj7me0IkAAA4Nm30UtdoNfPWYszZfhFXwLfuUZFn6Qu/U6UBb8PZsR3"
    encoded .= "zExcS7P2t5QZ2Ob7ITZoX4a047HZPECadXfLXvtG6fBLC3TiVzR/jFtRMJM+n1P6WVH3DgHSay9aAABzz73v/yx+xeH2Gahos6JGdf3sX6Ohi/P24Ve02bxG"
    encoded .= "5/fkoj6f84+vnoTma75i7KXzufJaGre/bTP5HeZzzbpPOTY77GB7VX9KP2ft88BDAiQAeOGN5oIX6M1n/7E/amqdWZ11gT63RkX9HFGj0YvzluFXtLlyjax5"
    encoded .= "WHYTrvtZ2GCBDV2idZ+gmtLP9H0pdy3lTuzv1tLnc0o/K+re5NgXIAHs/I4q/bKvwKPoraQpNZ/G3vwstNUF+hFjX7mfu1x6aHKHR/MaFX2Suu4Tyv3XfMXY"
    encoded .= "R3zie9xamr7FVW9i+86nuxw6H5t93gFuX/0p/Zy1zwOPCJAAWrzdqfjsg7dH6e9HTan5bDJ2n3afe0KrRgAAAEwhQAIAAAAAACAQIAEAAAAAABAIkAB28/Xb"
    encoded .= "9yf/u1ubCmRKzWe3sT/345Zo56KrEQAAALMIkAD29PXb9/s/zdtcuUBP/jfm09h3n8ZL/3bLNqeMfeV+bjzw64Zf0Wb/GlXM0kXN5nagw5qvGHvdfK68lqZv"
    encoded .= "cdWb2L7zuWbdpxybfd4Bbl/9Kf2ctc8DjwiQAOCFd5kCOfPZcOyPmlpnVivu7Cm6Wyi9RlPualr27qtBAac75Kx5WG0TrvtZ2GCBDV2iFc9ZmdXP9H0pdy2l"
    encoded .= "f5S5aD6n9LOi7k2OfQESAMDg09EFA7mKxyHWPWIxPTgccUFh2UdWzgo429ao6JP+RXd0jVjzg+6Qs5bG7W/bTP6Um/kEUXsdmx12sL2qv/hdOO4OhA28+vnj"
    encoded .= "V+kv+Pjhi1kGAAAW8f7d24f/b8oFi4o2Z03jn66bhBPNHn5WK8Y+Yj6tpc1m8pZJyJrPizqZ277L0/semxXrM7fNKxZnRcvbL9SrB35+h1PWUl0/0/elxLV0"
    encoded .= "46hPNJ47n1P6WVH3M9v59PlN3VEsQAIAAKCdugu1CwZypWPvP5/W0gYzmTIPKfO5wcX0lfeQzsdmxfrMbbMu4Kw+NjfYN+pmoK465/+W9H0pcS2lZDPp0VRR"
    encoded .= "1rVBPyvqfk47AiQAAABW5EIt1lLzmWw4q50vplN9bHa+23LZO+Tq7r7KXUul/ewcRhaFKOnzOaWfFXV/sR0BEgAAAABdNA/kih5dyMrrM6vNEXfybX9INjlI"
    encoded .= "S/uZvi8lrqWiEKXz4/vG1f10OwIkAAAAALjAk5fbREf0XJmHX6XNv6tps37m7kuJa6koROn8+L5xdT/RSQESAAAAAMBBrBlwTgnPZoV8WWupLkTJnc8p/dxy"
    encoded .= "ZQqQAAAAAAAYb0p4tmDIV/qIxcT5nNLPzWokQAIAAAAAAMoJ+WbVqDRA+svxAAAAAAAA3M3JYFb+Wrs49sIA6bXjAQAAAAAAgIfcgQQAAAAAAJBv9KP2BEgA"
    encoded .= "AAAAAE/zfTBgfSaO+uFf9Z8BARIAAAAA7MNF/3HVefhXTSp1gIvUjnfH0TqjnjUDr37++FX6Cz5++GJrAAAAAA7m0bWhlKs/FW2az7bz+eLlxVs6vPJa2qxA"
    encoded .= "TeZ2Sj8X35eWPd4nrs/b5/PMUWf9lk+f39TNhgAJAACAplwApedaOnFh6OqWK9ocWp1F5rPuourKa2nj6uw+t1P6OfH1Pfc4WvN43zhE6fP6fsXAb/wVAiQA"
    encoded .= "AADWMusCqKCr83z2vwi48t0Dy87nRZcX069aZsVyB75LTIA0ZU8esS8NPd77r8+er+9Xp0e3tC9AAgAAYCGDHvMi6Nqs9Nf1NnctVVwELLqweIwjved8tn20"
    encoded .= "UenYl7pLbIO7B6b0s/mePGJfmni8j1ifbV/fSwOk5xovDZBeOzMBAID3794+/GNCsOb37Vvuef7pH7xl+Kd/tv/Ezir9Fb0tXUssu3neuISuW3L7LtSKva7t"
    encoded .= "/ln3ojCun/bkvcp0gEmoXp9t19Ltv7Rh9QVIAACsru6iasXV+ZVTLglf/zW/5Yl34qWruus7/Sd2Vukv6m36WqrICbbJHqZsRP3ns/NxVDf2vWbey709+UjH"
    encoded .= "0Zr9nPJe8ah1zyJAAoAXXqFd/F2wRiv30+lx1hv0R+VOqX5Fm7OO9DXHPmXNT7/ccOzhrzx2aHUcTbm7RZWbl+mQdzlYTocp0LLrM/EziK3GJUACuGAH94nv"
    encoded .= "ld/wVbwVaD6lI+o+ZT4H1d15nVNrrPlBJ947foJ+xCepi8a+b+n3+jRxn4d0HeO1adx8Nj+OOtxGue+/ZLU9edZxtGY/p7xXPHbdUwiQAC7eqVd7F7vs2Cse"
    encoded .= "79P/uwdm1X3KfA6qO9Xv7ys+h7jCclp57AAAAHsRIAEAAAAAABAIkAAAAAAAAAgESABn+frt+5P/beyLDDxr+BVtrlz3KfM5qO7UFf320le0ufJ8AgAAcJoA"
    encoded .= "CeBcX799v/9j7EsN/Mn/7tbmynWfMp8rh9CDDvNL/xas+Y27d8u/P+dfXvTbc3/17rM6qPRn/sv0tXTdFFUcccd4bRo3n82Po7qxV+x1g/ZP7xba7smzjqM1"
    encoded .= "+znlveKx655CgAQAL7xIp4coK4eRU2q0cj+dIWe9R39U7pTqV7Q560hfc+xT1vz0Kw7HHr6wHJocRxX3IrNZlfuUaUo/Lac1C7Ts+qz42HEHAiQAAJzdVT1m"
    encoded .= "UAidXinRUfM1v+U58xV9zg3PRtzZUzT2vUq/711iFZ+gH/Gp/N0P9j7z2fk4GnQH57j901uFnnvyrONozX5Oea941LpnESABAMD/kgn5BNb8iOsCV/c5Nzyb"
    encoded .= "dWdP/+/kS59PF6lpeBxNfPzU9g8PHPc8wO27vUE/7cl7lekAk1C9PtuupUPeffXq549fpb/g44cv3l4AAABwkffv3g46tX7UW5lEq/nMXUsnWru65Yo2D3Ck"
    encoded .= "H3s+z+zkpV2tHnvFXtdz/7yoQDv2fJt+dt6TR+xLQ4/3/uuz5+v7FaO+vf1Pn9/U1VGABAAAQFOCGXqupYoLoLNC09LqLDKfdRd/V15LG1dn97md0s+Jr+/9"
    encoded .= "P3zQ/3hfNuC8OkO6+lcIkAAAAAB6WeduDPO5zZD/dEuHBfAbFKjJ3K58F+OgfWnZ433i+rx9PjcOzwRIAAAAAHBAT15ndK2/c3UaVmpKP1nzeF9zfRY9uvBJ"
    encoded .= "f//zr7qBCJAAAAAAAJ425aK/MBLH0YhRp89AaYD0l7ULAAAAAPCkKde4ZUVYnz1HPTo8EyABAAAAAADkGx2evVY/AAAAAAAAHir/DqQ7X4MEAAAAAACQ4fdj"
    encoded .= "8T59flP6izzCDgAAAAAA/qfie2umfBfOyv1sPvYnu1fKHUgAAAAAADw2JUjYYNQ3zkBFm1PGrkalo66+A0mABAAAAAAvc/eAGnXuZ26bU4KE3LFfdHvHme1X"
    encoded .= "tLnZHC7Sz+qxp6zP5zopQAIAAACAPbl7QI069zO9zTOvp3eY0sSxX/FwsBcbr2hzl2k8cD9Lx561Pk+0c4QA6U6GBAAAAHt7dPUh5dJPRZv0r/vic/icrFs9"
    encoded .= "6m4ZadLPiTXq3M/cNrcJEhqu+au/WuZE4xVtVsznyv0sHXvW+twxPboTIAEAACxIkLB4xVMqVdEm/es+a1+qnsbbJzaxRlP6WVH3DR691baf6W1WB0g91/zV"
    encoded .= "KcKJxivarJjPlftZOvas9Xm6HQESAADA6nIvqgoSLKGUMo17TNaUgDOxn4Nq1HkPGfFoo0H9rKj7lMBjxKO3qu9EabvmhwZIKfO5cj/rxp61Pl9sR4AEAMBs"
    encoded .= "7kgwn+QW/cbSCxIsoZQyDfpujIrjaEQ/1/z+kr0On+v63PzRW9VraYPvBdmm/R37md5mdZDQds3fOPAnW65os2I+V+5n3dgT12eHAOn1Nq+4f//zL+/aAWCW"
    encoded .= "9+/e3v9p3qb57Nzmn+2sWf3E6iw+nwvuIc8N9rpJOOenLm25ok02WELd/uWg42hEPwfVaNk9ZEqNivo5pe5e4xZc8+ZT3QfZID262yxAAgAevjFqfgH0UfdS"
    encoded .= "elvR5qyK95/P9DZLL9gJElY711pzDzk9RqfZcKTjyPE+bvHU/exR+6lGfd4BPvmzKWcTE+ez4pNzdZ/G6zOT0/vZ8xOTj362yRa9XYDkJiTgAOcPy945QdFb"
    encoded .= "H8uJRZZ6+jnAgseRC4sOottL704Uq2j7VXc34YPPx7vLYVCNlt1DptSoqJ/unPB6ZErtIep+u21uP7pzBxLAFS9j6U+LMr0rv89ruAA2+4zbIut/ynwOqpHH"
    encoded .= "uNk8lR4AAGADAiSAPd1f+XL9CwAAAABoZdMAyVPsAB75+u377/8LAAAAAHDCZs+vu3MHEsCZHmY8uXmP9GjZhdR2ATzXpVu6WtHm3KL3nM9BNRpxHNH/OAIA"
    encoded .= "AOC0rQMkNyEBc3399v3+j6ngxoX05H/DgZf6pX/rONp4PplY9CtKf/4/3vdfsvEqKl11u5e+YkT9+zmoRsvuIVNqVNTPKXX3Grfgmjef6j7Clrcf3bkDCQB2"
    encoded .= "eRfVPIx81L2U3la0Oavi/eczvc3Su0YWDPUXvwtnzT1EcAjrHEeO93GLp+5nj9pPNerzDvDJn005m5g4n1ndrviIW/WUrtzPurEnrs8mW/QOAZKbkABgyvlY"
    encoded .= "+iXale/kmzKfuW163Fz1udNq8yk4vLH0e91f4sBvuIS6/ctBx9GIfg6q0bJ7yOJ34ax5d6DXo1mvHeZT3Xva+Paju7u7Vz9//NplqB8/fFFvAACAF71/9zbx"
    encoded .= "BPtRayktV7RJ3RJKKVNFm4OOoxH9HFSjznvIi9N4S58TazSlnxV1Lx17836mt3lFgxdNRds1f/XAT7Rc0WbFfK7cz7qxZ63PR+1snx7dCZAAAAAWVHExfcoF"
    encoded .= "ehV/RHCo7gfel6qn8faJTazRlH5W1L107M37md7mlEAud+xDA6SU+Vy5n6Vjz1qfD9tZK0C6kyEBAADAhgSH6q5GKXP4nKw4tiLWbdXPiTXq3M/cNqsDpLZr"
    encoded .= "vuLuq+o7urLmc+V+lo49a33et7NLenS3b4B0J0MCAAAAoL0pjwQc93hJNUrpZ3qbUwK5u/aPgtwmkNtgGg/czxGPAP37n3/tdYjtHCDdyZAAAAAAmODJS4H9"
    encoded .= "nwfYtp9qlNvP3DZnhZFZYx/xmMEt53CRflaP/cb1uWN6dCdAAgAAAADgT2uGkSPuEhs0djW60eoB0p0MCQAAAACANvrfJTZr7Gp0nX3To7smAdKdDAkAAAAA"
    encoded .= "AODu7q5BenR3d/faXAAAAAAAADTRJDF5bUYAAAAAAAA66JOVdHmE3W+eZQcAAAAAwI6mfA8Qx9PqTpt2AdKdDAkAAAAA6EGQoOJZ1V95LU0Z++797Pacto4B"
    encoded .= "0j0xEgAAAACwl7ogYbPeCrpyK3713K68lqYEcrvXqOdX/PQNkO5kSAAAAAB08ugKY8r1xIo2V57Por49p0OfSy98r7M+L0qPLpqN6rWUWKP0tVQ09in9PL9G"
    encoded .= "PdOju+YB0p0MCQAAALjZyhf9V+5nbpsnLi9WfOC9/5OdGs5nVj/rgoQN6pLYw1nrc5tpvHQqqtdSbo1y19KUQK5DjdqmR3f9A6R7YiQAAADackfCoOqkzOqU"
    encoded .= "i6or97PzRdW6NqfUqH/gMShAKnrk2qz1efvr5tXp0Yu/a9BdTelrqWjsU/p5ZsufPr9p/j5qRoB0J0MCAACgH3ckzC3Q1VM65XssVu5nbpsVF+jrvmelf436"
    encoded .= "f8dM0Z0ou5Tmuk7OWp8pr5tFAVLdWuofoky5o2vfGvVPj+4GBUj3xEgAAE++H/Vpd2NH3e1Luw/5T93CidXW/Mp3jazcz/6fyr8bdYF+xHwm9rPuTpS9SlM9"
    encoded .= "CQcIOG8s+nO/pXQt5dYofS1NCeR2rNGI6Oje61lv/v7+51+dHwgIALDXadLtpz0Vba48n7x/9/b+z4J1rxj7mvPZ/Ng8pzOXdriizWX3uvNHt++/nDL2ZWvU"
    encoded .= "4SjesUwj5nPQmj/Y5jllGzle0WfVyHH0yKfPbwalR3fjAqR79zGSJAmAP1+hm19cY82Lqpu9Gb1lEiraXHk+HekPZ6/nEVpU94qxLzufjk17HUCTrXLLFjb4"
    encoded .= "RXb+itl41M7Ka6lo7FP6+Zz73GhWdHTv9egjXIwEbPyuYtlwYsTYH11cs2IXqdGCdT89zOsmoaLNlecTdTefK+xLs+5uWXDNr3zXyMr9TG+zzw62S5lGzOed"
    encoded .= "uzF2LfqUbeRIRZ9VI8fR3cBbjh756wAleZgh+ZIkYIPd//27t8t+L0jbsT/5SBZfZXH4Gqk7DDqnXeHwrBj7yvMJAAATjU6MHvnrYLV5dEOSPAkAAAAAAChy"
    encoded .= "4Mekvfr545cCAwAAAAAA8NtrUwAAAAAAAMBDAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgE"
    encoded .= "SAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgES"
    encoded .= "AAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQA"
    encoded .= "AAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAA"
    encoded .= "AAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAg+Otg4/m//5//S1Ghwv/78/8zCfY3AADA"
    encoded .= "+RcAsIhXP3/8Gj0AV1TB+cxR2d8AAADnXwDAXqYGSK6rgjOZo7K/AQAAzr8AgN0NC5BcVwVnMkdlfwMAAJx/AQB9zAiQXFcFZzJHZX8DAACcfwEADXUPkFxa"
    encoded .= "BacxR2V/AwAAnH8BAG31DZBcWgWnMUdlfwMAAJx/AQDNve7ZLVdX4Rgcy+YEAABwrgEATNTuDiRvd+CQfBTO/gYAADj/AgAG6XUHkqurcFSObjMAAAA4+wAA"
    encoded .= "BulyB5I3N7CIBT8KZ38DAACcfwEA47S4A8nVVVjHase7/Q0AAHA+AgBMtH+A5N0MOIcxUgAAAGclAEArOwdI3seAcxhjBAAAcG4CAHSz23cgefsC3B30kdz2"
    encoded .= "NwAAwPkXADDdPncguboKHHU3sL8BAADOVgCAA9ghQPJ+BTjqnmB/AwAAnLMAAMfw2hQAAAAAAADw0NYBko+6AEfdGexvAACAMxcA4DA2DZC8RwGOuj/Y3wAA"
    encoded .= "AOcvAMCRbBcgeXcCHHWXsL8BAADOYgCAg9koQPK+BDjqXmF/AwAAnH8BAMfz2hQAAAAAAADw0BYBko+0AEfdMexvAACA8y8A4JDKAyTvRYCj7hv2NwAAwPkX"
    encoded .= "AHBUHmEHAAAAAABAUBsg+RgLcNTdw/4GAAA4/wIADqwwQPL+AzjqHmJ/AwAAnH8BAMfmEXYAAAAAAAAEVQGSj64AR91J7G8AAIDzLwDg8NyBBAAAAAAAQFAS"
    encoded .= "IPnQCnDU/cT+BgAAOP8CAFbgDiQAAAAAAAACARIAAAAAAABBfoDkfmfgqLuK/Q0AAHD+BQAswh1IAAAAAAAABAIkAAAAAAAAguQAyZ3OQIUOe4v9DQAAcP4F"
    encoded .= "AKzDHUgAAAAAAAAEAiQAAAAAAACCzADJPc5AnX13GPsbAADg/AsAWIo7kAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAEFagOT7FYFqe+0z9jcA"
    encoded .= "AMD5FwCwGncgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAA"
    encoded .= "AAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAA"
    encoded .= "AAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAA"
    encoded .= "AACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAA"
    encoded .= "ACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAA"
    encoded .= "CARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAAC"
    encoded .= "ARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECA"
    encoded .= "BAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECAB"
    encoded .= "AAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAA"
    encoded .= "AAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAA"
    encoded .= "AAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAA"
    encoded .= "AEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAA"
    encoded .= "EAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAE"
    encoded .= "AiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEA"
    encoded .= "CQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEAC"
    encoded .= "AAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAA"
    encoded .= "AAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAA"
    encoded .= "AAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAA"
    encoded .= "AIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAA"
    encoded .= "IBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAI"
    encoded .= "BEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIB"
    encoded .= "EgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAE"
    encoded .= "AAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEA"
    encoded .= "AAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAA"
    encoded .= "AAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAA"
    encoded .= "AACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAA"
    encoded .= "QCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQ"
    encoded .= "CJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQC"
    encoded .= "JAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJ"
    encoded .= "AAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIA"
    encoded .= "AAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAA"
    encoded .= "AAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAA"
    encoded .= "AAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAA"
    encoded .= "gECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAg"
    encoded .= "ECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgE"
    encoded .= "SAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgES"
    encoded .= "AAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQA"
    encoded .= "AAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAA"
    encoded .= "AAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAA"
    encoded .= "AAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAA"
    encoded .= "AIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABA"
    encoded .= "IEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAI"
    encoded .= "kAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIk"
    encoded .= "AAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkA"
    encoded .= "AAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAA"
    encoded .= "AAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAA"
    encoded .= "AAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAA"
    encoded .= "AAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACA"
    encoded .= "QIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQ"
    encoded .= "IAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARI"
    encoded .= "AAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIA"
    encoded .= "AAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAA"
    encoded .= "AAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAA"
    encoded .= "AAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAA"
    encoded .= "AAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAA"
    encoded .= "gQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAg"
    encoded .= "QAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQ"
    encoded .= "AAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQA"
    encoded .= "AAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAA"
    encoded .= "AAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAA"
    encoded .= "AAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAA"
    encoded .= "AAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAA"
    encoded .= "AgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBA"
    encoded .= "gAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAg"
    encoded .= "AQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgA"
    encoded .= "AAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAA"
    encoded .= "AAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAA"
    encoded .= "AABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAA"
    encoded .= "ABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBAAgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAA"
    encoded .= "BAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACB"
    encoded .= "AAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAAAAAAAAIBEgAAAAAAAIEACQAAAAAAgECABAAAAAAAQCBA"
    encoded .= "AgAAAAAAIBAgAQAAAAAAEAiQAAAAAAAACARIAAAAAAAABAIkAAAAAAAAAgESAAAAAAAAgQAJAAAAAACAQIAEAAAAAABAIEACAAAAAAAgECABAAAAAAAQCJAA"
    encoded .= "AAAAAAAIBEgAAAAAAAAEAiQAAAAAAAACARIAAAAAAACBAAkAAAAAAIBAgAQAAAAAAEAgQAIAAAAAACAQIAEAAAAAABAIkAAAAAAAAAgESAAAAAAAAAQCJAAA"
    encoded .= "/v/27iC1jSAIoCgZCDj3v2sc4k0WAeHvrTXTPaX3LhBJgaJLf9oCAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAA"
    encoded .= "AAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgB"
    encoded .= "CQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAA"
    encoded .= "AIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAA"
    encoded .= "AAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAA"
    encoded .= "CAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAA"
    encoded .= "AAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQ"
    encoded .= "kAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAA"
    encoded .= "AAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJ"
    encoded .= "AAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAA"
    encoded .= "gBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAA"
    encoded .= "AAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAI"
    encoded .= "AQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAA"
    encoded .= "AACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQ"
    encoded .= "AAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAA"
    encoded .= "AAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkAAAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAAAIAQkA"
    encoded .= "AAAAAIAQkAAAAAAAAAgBCQAAAAAAgBCQAAAAAAAACAEJAAAAAACAEJAAAAAAAACIpwWkP+8fPk3gVKvmjPkGAADYvwCAV+MGEgAAAAAAACEgAQAAAAAAEAIS"
    encoded .= "AAAAAAAAISABAAAAAAAQzwxIfl8ROM/aCWO+AQAA9i8A4KW4gQQAAAAAAEAISAAAAAAAAMSTA5I7zsAZdpgt5hsAAGD/AgBehxtIAAAAAAAAhIAEAAAAAABA"
    encoded .= "PD8guekMTJ0q5hsAAGD/AgBehBtIAAAAAAAAhIAEAAAAAABAnBKQ3HcGps4T8w0AALB/AQCvwA0kAAAAAAAA4qyA5KEVYOokMd8AAAD7FwAwnhtIAAAAAAAA"
    encoded .= "xIkByaMrwNQZYr4BAAD2LwBgtnNvIDl/AFOnh/kGAADYvwCAwfwJOwAAAAAAAOL0gOQxFmDq3DDfAAAA+xcAMNUVN5CcRYCpE8N8AwAA7F8AwEj+hB0AAAAA"
    encoded .= "AABxUUDySAswdVaYbwAAgP0LAJjnuhtIziXA1ClhvgEAALYYAGCYS/+EndMJMHU+mG8AAID9BQCY5OrfQHJGAaZOBvMNAACwuQAAYxw+AgAAAAAAAD5bEJA8"
    encoded .= "6gJMnQnmGwAAYGcBAGZYcwPJeQWYOg3MNwAAwLYCAAzw4/3334X//Nuvn/4PwOoykvkGAADYvwCA+1r8G0hOMGB78R4BAADsJgDAbo7lr8A5Bmwv3ikAAICt"
    encoded .= "BADYyrHDi3CaAduL9wsAAGAfAQD2sfg3kL7wkyFgdZnKfAMAAOxfAMCNHFu9GucbsL34BAAAAGwfAMBye91AevCoPlhdpjLfAAAA+xcAsL9jz5flxAO2F58J"
    encoded .= "AACAXQMAWGXTG0gPHtUHq8tU5hsAAGD/AgC2tXtA+s/XrGB1mcp8AwAA7F8AwIbuEZAefNMK9papzDcAAMD+BQDs42YB6cE3rWBvmcp8AwAA7F8AwHJ3DUgP"
    encoded .= "vmkFe8tU5hsAAGD/AgBWuX1A+sL3rWBjmcp8AwAA+xcAwGWmBSQAAAAAAAC+6fARAAAAAAAA8JmABAAAAAAAQAhIAAAAAAAAhIAEAAAAAABACEgAAAAAAACE"
    encoded .= "gAQAAAAAAEAISAAAAAAAAISABAAAAAAAQAhIAAAAAAAAhIAEAAAAAABACEgAAAAAAACEgAQAAAAAAEAISAAAAAAAAISABAAAAAAAQAhIAAAAAAAAhIAEAAAA"
    encoded .= "AABACEgAAAAAAACEgAQAAAAAAEAISAAAAAAAAISABAAAAAAAQAhIAAAAAAAAhIAEAAAAAABACEgAAAAAAACEgAQAAAAAAEAISAAAAAAAAISABAAAAAAAQAhI"
    encoded .= "AAAAAAAAhIAEAAAAAABACEgAAAAAAACEgAQAAAAAAEAISAAAAAAAAISABAAAAAAAQAhIAAAAAAAAhIAEAAAAAABACEgAAAAAAACEgAQAAAAAAEAISAAAAAAA"
    encoded .= "AISABAAAAAAAQAhIAAAAAAAAhIAEAAAAAABACEgAAAAAAACEgAQAAAAAAEAISAAAAAAAAISABAAAAAAAQAhIAAAAAAAAhIAEAAAAAABACEgAAAAAAACEgAQA"
    encoded .= "AAAAAEAISAAAAAAAAISABAAAAAAAQAhIAAAAAAAAhIAEAAAAAABACEgAAAAAAACEgAQAAAAAAED8A9AE9ErDuJWYAAAAAElFTkSuQmCC"
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
    ; The test uses the selected axis immediately, as StartZoom does.
    direction := C["Axis"].Value = 1 ? "вверх / вниз" : "влево / вправо"
    tone := "82798E"
    if !Enabled {
        message := "Зум на паузе.`nНажми «Продолжить» слева."
        tone := "8B490E"
    } else if !WinActive("ahk_id " SettingsUI.Hwnd) || !OverTestCanvas() {
        message := "Зажми сочетание на тестовом холсте.`nДвигай мышь " direction "."
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
        message := "Сочетание зажато — всё готово.`nДвигай мышь " direction "."
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
    ; Compose the percentage in the same frame as the grid and zoomed shape.
    dpi := A_ScreenDPI / 96
    badgeX := Round(12*dpi), badgeY := h-Round(48*dpi)
    badgeW := Round(80*dpi), badgeH := Round(34*dpi)
    SmoothRound(dc,badgeX,badgeY,badgeW,badgeH,10*dpi,"FFFFFF")
    badgeRect := Buffer(16,0)
    NumPut "Int", badgeX, badgeRect, 0
    NumPut "Int", badgeY, badgeRect, 4
    NumPut "Int", badgeX+badgeW, badgeRect, 8
    NumPut "Int", badgeY+badgeH, badgeRect, 12
    badgeFont := SendMessage(0x31,0,0,C["TestPercent"].Hwnd)
    previousFont := DllCall("SelectObject","Ptr",dc,"Ptr",badgeFont,"Ptr")
    DllCall("SetBkMode","Ptr",dc,"Int",1)
    DllCall("SetTextColor","Ptr",dc,"UInt",ColorRef("6344D7"))
    DllCall("DrawTextW","Ptr",dc,"Str",Round(TestScale*100) "%","Int",-1,
        "Ptr",badgeRect.Ptr,"UInt",0x25)
    DllCall("SelectObject","Ptr",dc,"Ptr",previousFont)
    DllCall("SelectObject","Ptr",dc,"Ptr",previous)
    DllCall("DeleteDC","Ptr",dc)
    ; Swap complete frames; owner drawing copies the frame without erasing.
    oldBitmap := TestBitmap
    TestBitmap := bmp
    DllCall("RedrawWindow", "Ptr", C["Canvas"].Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x101)
    DllCall("RedrawWindow", "Ptr", C["TestPercent"].Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x101)
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
