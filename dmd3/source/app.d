import storm.minigdiclock;

version(Windows)
{	
	import core.sys.windows.windef;
	import core.sys.windows.winuser;
	import core.sys.windows.wingdi;
	pragma(lib, "gdi32.lib");
}

import std.stdio;
import std.exception;
import std.conv;
import std.utf;

@system:

MiniGdiClock mclock;
 
extern(Windows)
{
	static timer(HWND handle, UINT param1, UINT_PTR param2, DWORD param3)
	{
		HDC hdc = GetDC(handle);
		mclock.run(hdc);
		DeleteDC(hdc);
	}
	LRESULT Processor (HWND handle, UINT message, WPARAM wParam, LPARAM lParam)
	{
		switch(message)
		{
			case WM_CREATE:
				mclock = new MiniGdiClock();
				SetTimer(handle, 100, 1, cast(TIMERPROC)&timer); 
				return 0;
			case WM_LBUTTONUP:
				auto x = LOWORD(lParam);
				auto y = HIWORD(lParam);
				if(mclock.clockClicked(x,y))
				{
					HDC hdc = GetDC(handle);
					mclock.toggleHourSpec();
					mclock.run(hdc);
					DeleteDC(hdc);
				}
				return 0;
			case WM_SIZE:
				return 0;
			case WM_PAINT:
				PAINTSTRUCT ps;
				HDC hdc = BeginPaint(handle, &ps);
				//---
				EndPaint(handle, &ps);
				return 0;
			case WM_DESTROY:
				PostQuitMessage(WM_QUIT);
				return 0;
			default: 
				return DefWindowProcW(handle, message, wParam, lParam);
		}
	}
}

class Window 
{
	extern(Windows)
	{
		static LRESULT MainProc (HWND handle, UINT message, WPARAM wParam, LPARAM lParam)
		{
			switch(message)
			{
			default:
				return CallWindowProc(cast(WNDPROC)&Processor, handle, message, wParam, lParam);
			}
		}
	}
	this(string title = "D Application", string icon = "", int width = 100, int height = 100, int positionx = 0, int positiony = 0) 
	{
		this.title = title;
		this.width = width;
		this.height = height;
		this.px = 0;
		this.py = 0;
		this.icon = LoadImage(null, toUTFz!(wchar*)(icon), IMAGE_ICON, 0, 0, LR_LOADFROMFILE);
		this.bgBrush = bgBrush = cast(HBRUSH)COLOR_WINDOW;
		this.cursor = cursor = LoadCursorW(null, IDC_ARROW);
		this.style = style = CS_DBLCLKS|CS_HREDRAW|CS_VREDRAW|WS_CLIPSIBLINGS;
		windowClassName = toUTFz!(wchar*)("DApplicationClassW");
		Register();
		Create();
	}
	~this() 
	{
		UnregisterClass(cast(wchar*)registeredAtom, hInstance);
	}
	static repaintWindow(HWND handle)
	{
		InvalidateRect(handle, null, true);
		SendMessage(handle, WM_NCPAINT, 0, 0);
	}
	auto Register()
	{
		windowClassExW.cbSize = WNDCLASSEXW.sizeof;
		windowClassExW.style = this.style;
		windowClassExW.lpfnWndProc = cast(WNDPROC)&MainProc;
		windowClassExW.cbClsExtra = this.cbClsExtra;
		windowClassExW.cbWndExtra = this.cbWndExtra;
		windowClassExW.hInstance = this.hInstance;
		windowClassExW.hIcon = this.icon;
		windowClassExW.hCursor = this.cursor;
		windowClassExW.hbrBackground = this.bgBrush;
		windowClassExW.lpszMenuName = toUTFz!(wchar*)(this.menuName);
		windowClassExW.lpszClassName = this.windowClassName;
		windowClassExW.hIconSm = this.iconSm;
		registeredAtom = RegisterClassExW(&windowClassExW);
		enforce(registeredAtom, "failed to register Window class!");
		return this;
	}
	auto Create()
	{
		this.handle = CreateWindowExW ( 
			0,
			cast(wchar*)this.registeredAtom,
			toUTFz!(wchar*)(this.title),
			WS_OVERLAPPEDWINDOW,
			this.px,
			this.py,
			this.width,
			this.height,
			null,
			this.menu,
			this.hInstance,
			null
		);
		enforce(this.handle, "failed acquiring HWND to Window!");
		return this;
	}
	auto Show()
	{
		ShowWindow(this.handle, SW_SHOWDEFAULT);
		UpdateWindow(this.handle);
		return this;
	}
	auto loop()
	{
		Show();
		MSG msg;
		BOOL ret = false;
		while((ret = GetMessageW(&msg, null, 0, 0)) != 0)
		{
			if(ret == -1) break;
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
		return ret;
	}
	auto _handle() 
	{
		return this.handle;
	}
private:
	WNDCLASSEXW windowClassExW;
	HINSTANCE hInstance = null;
	ATOM registeredAtom = 0;
	HWND handle = null;
	string title = null;
	HICON icon = null;
	HBRUSH bgBrush = null;
	HCURSOR cursor = null;
	uint style = 0;
	const(wchar*) windowClassName;
	auto px = 0;
	auto py = 0;
	auto width = 0;
	auto height = 0;
	int cbClsExtra = 0;
	int cbWndExtra = 0;
	string menuName = null;
	HMENU menu;
	HICON iconSm = null;
}


void main(string [] args) 
{
	version(Windows)
	{
		Window MyWindow = new Window("MiniGdiClock", "", 220, 260);
		MyWindow.loop();
	}	
}