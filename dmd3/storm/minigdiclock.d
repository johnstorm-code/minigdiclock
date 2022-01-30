/* 
 * File:   minigdiclock.d
 * 
 * Copyright (C) 2022  jstorm
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Created in January 2022
 */

module minigdiclock;

version(Windows)
{
	import core.sys.windows.windef;
	import core.sys.windows.wingdi;
	import core.sys.windows.winuser;
	pragma(lib, "gdi32.lib");
}

import std.stdio;
import std.conv;
import std.exception;
import std.math;
import std.datetime;
import std.utf;
import core.stdc.stdlib;
import std.file;

class MiniGdiClock
{
private:
	/*
	 * Check for regenerating the backbuffer bitmap
	 */
	bool redoBackbuffer;
	/*
	 * The bounding box for the clock object is composed of these coordinates
	 */
	int left;
	int top;
	int right;
	int bottom;
	/*
	 * The main Clock Radius;  this value defines the OUTER area of the clock's face
	 */
	double radius;
	/*
	 * The INNER radius;  this value defines drawing within an inner area from the radius
	 */
	double iradius;
	/*
	 * The center point of the clock circle
	 */
	POINT center;
	/*
	 * These are used to define cases specific to this domain 
	 */
	immutable enum byType { Hour = 0, Minute = 1, Second = 2 };
	/*
	 * A list of colors used throughout;  new colors can be defined here
	 */
	immutable enum colors { 
		Black = RGB(0,0,0), 
		Pink = RGB(255, 71, 231), 
		Gray = RGB(157, 159, 161), 
		Teal = RGB(10, 122, 110), 
		Purple = RGB(138, 28, 138), 
		Goldenrod = RGB(190, 172, 40), 
		Crimson = RGB(237, 76, 87), 
		DarkGray = RGB(41, 41, 41) 
	};
	/*
	 * The minimum angle in degrees from which we draw
	 */
	immutable int minangle = -360;
	/*
	 * the maximum angle in degrees from which we draw
	 */
	immutable int maxangle = -minangle;
	/*
	 * The angles in 1 hour in degrees (360/12)
	 */
	immutable int anglesInHour = to!int((maxangle / 12.0));
	/*
	 * The direction we draw;  this allows us to go in clock-wise direction
	 */
	immutable int anglesDirection = -90;
	/*
	 * The angles in 1 minute in degrees 
	 */
	immutable int anglesInMinute = to!int((maxangle / 60.0));
	/*
	 * The angles in 1 second in degrees 
	 */
	immutable int anglesInSecond = anglesInMinute;
	/*
	 * The angle minute;  defines the number of degrees an 1 minute within 1 hour;  This is used to calculate how much to move the hour hand relative to the hour, so that the hour hand moves closer to the next hour as the minute hand is closest to 60
	 */
	immutable double angleMinute = (anglesInHour/60.0);
	/*
	 * The GDI HPEN object used to draw lines, circles, etc
	 */
	HPEN hpen;
	/*
	 * The REGION of the clock;  this allows us to perform hit testing
	 */
	HRGN region;
	/*
	 * A control variable for 24/12 hour clock 
	 */
	bool display24HourSpec;
	/*
	 * This is a buffer used to re-paint "static" backgound of the clock rather than redraw-it
	 */
	HBITMAP backbuffer;
	/*
	 * Sets the Region of the clock based on the whole area it occupies
	 */
	final void setRegion()
	{
		RECT r = getClientRect();
		if(region) DeleteObject(region);
		region = CreateRectRgn(r.left, r.top, r.right, r.bottom);
		enforce(region);
	}
	/*
	 * For all DRAW operations, we must first create a PEN with properties for drawing;  this selects the pen and uses it within the device context we want to use to draw upon
	 */
	final void startPen(HDC hdc, int penstyle, int penwidth, COLORREF color)
	{
		hpen = CreatePen(penstyle, penwidth, color);
		enforce(hpen);
		SelectObject(hdc, hpen);
	}
	/*
	 * Once the pen is no longer needed, we must delete it;  IT MUST be called to ensure no GDI object leaks
	 */
	final void endPen()
	{
		DeleteObject(hpen);
	}
	/*
	 * Copies the clock area to a backbuffer bitmap
	 */
	private void backbufferBitmap(HDC hdc)
	{
		RECT r = getClientRect();
		auto width = r.right - r.left;
		auto height = r.bottom - r.top;
		auto chdc = CreateCompatibleDC(hdc);
		backbuffer = CreateCompatibleBitmap(hdc, width, height);
		SelectObject(chdc, backbuffer);
		StretchBlt(chdc, 0, 0, width, height, hdc, r.left, r.top, width, height, SRCCOPY);
		BitBlt(hdc, left, top, width, height, chdc, 0, 0, SRCCOPY);
		DeleteObject(chdc);
	}
	/*
	 * Copies from a backbuffer bitmap to a window device context
	 */
	private void copyBitmap(HDC hdc)
	{
		RECT r = getClientRect();
		auto width = r.right - r.left;
		auto height = r.bottom - r.top;
		auto chdc = CreateCompatibleDC(hdc);
		SelectObject(chdc, backbuffer);
		BitBlt(hdc, left, top, width, height, chdc, 0, 0, SRCCOPY);
		DeleteObject(chdc);
	}
public:
	/*
	 * The Default constructor simply places the clock at 0,0 and extends it to 100 pixels high/wide
	 */
	this()
	{
		this(0,0,100);
	}
	/*
	 * Constructor for a clock of size (radius length) and position x, y;  the clock is not drawn on construction, only sets up the various internal state of the clock and prepares it for drawing;  calling run() is the main entry method; or piece-by-piece via various methods
	 */
	this(int positionx, int positiony, int size, bool milspec = true)
	{
		setRadius(size);
		setPosition(positionx, positiony);
		setAreaRegion();
		/* Configuration for 12/24 hours */
		display24HourSpec = milspec;
	}
	/*
	 * Destructor simply ensures the region and backbuffers are recycled 
	 */
	~this()
	{
		DeleteObject(region);
		DeleteObject(backbuffer);
	}
	/*
	 * Returns the ACTUAL area occupied by the clock and text areas;  The BBOx is simply extended by the addition of the longest bottom
	 */
	final RECT getClientRect()
	{
		auto r = getRect();
		auto t = getTextTimeRect();
		r.bottom = t.bottom;
		return r;
	}
	/*
	 * Returns the Clock area BBOX in RECT struct form;  this is only the area of the clock excluding the text area
	 */
	final RECT getRect()
	{
		RECT r;
		r.left = left;
		r.top = top;
		r.right = right;
		r.bottom = bottom;
		return r;
	}
	/*
	 * Returns the BBOX of the text area of the clock in RECT struct form;  this is the area of the text excluding the clock;  It's calculated from the main clock area by simply adding 20 pixels to the bottom
	 */
	final RECT getTextTimeRect()
	{
		RECT r = getRect();
		r.top = r.bottom;
		r.bottom = r.top + 20;
		return r;
	}
	/*
	 * Helper function for clock; Converts degree in anle to radian, returns radian double
	 */
	final double degToRad(int angle)
	{	
		enforce(angle <= maxangle && angle >= minangle);
		auto rad = to!double(angle) * (PI/180.0);	
		return rad;
	}
	/*
	 * Gets the value of X from a specification in radian for a point x and radius 
	 */
	final int getX(double radian, double radius, int centerx)
	{
		auto x = (cos(radian) * radius)+centerx;
		return to!int(x);
	}
	/*
	 * Gets the value of Y from a specification in radian for a point y and radius 
	 */
	final int getY(double radian, double radius, int centery)
	{
		auto y = (sin(radian) * radius)+centery;
		return to!int(y);
	}
	/*
	 * Returns a POINT from a specification in radian for a poiny x and y and radius
	 */
	final POINT getXY(double radian, double radius, int centerx, int centery)
	{
		POINT p;
		p.x = getX(radian, radius, centerx);
		p.y = getY(radian, radius, centery);
		return p;
	}
	/*
	 * Returns a time value based on a type (minute, hour, second);  this value is returned as 24 hour LOCAL time
	 */
	final int getTime(byType type)
	{
		final switch(type)
		{
			case byType.Hour:
				return to!int(Clock.currTime().hour);
			case byType.Minute:
				return to!int(Clock.currTime().minute);
			case byType.Second:
				return to!int(Clock.currTime().second);
		}
	}
	/*
	 * Sets the length of the radius and re-calculate all values
	 * TODO: backbuffer breaks
	 */
	final void setRadius(int size)
	{
		radius = to!double(size);
		iradius = radius-5.0;	
	}
	/*
	 * recalclates the area region and painting 
	 */
	void setAreaRegion()
	{
		right = left + to!int(radius*2);
		bottom = top + to!int(radius*2);
		center.x = left + to!int(radius);
		center.y = top + to!int(radius);
		
		/* ALways setup a region so we can interact with hittesting */
		setRegion();
	}
	/*
	 * Sets the position of the clock
	 */
	final void setPosition(int positionx, int positiony)
	{
		left = positionx;
		top = positiony;
	}
	/*
	 * CONVENIENCE ENTRY function that draws all 
	 */
	void run(HDC hdc)
	{
		drawFace(hdc);
		drawMinuteHand(hdc, 3);
		drawHourHand(hdc, 2); 
		drawSecondHand(hdc);
		drawFilledCenter(hdc);
		drawTextTime(hdc);
	}
	/*
	 * Draws the face (background that remains static);  upon draw, it copies the drawing to a backbuffer to use for subsequent painting of the face;  this is a fairly drawing-intensive operation that involves:
	  1) filling
	  2) drawing markers (labvels) for both second and hours
	  So these are drawn once;
	  The redoBackBuffer variable allows regeneration of the backbuffer when the size of the clock is changed via radius or position;  the redoBackBuffer() must be called when the client changes either value
	 */
	void drawFace(HDC hdc)
	{
		if(redoBackbuffer)
		{
			DeleteObject(backbuffer);
			backbuffer = null;
			redoBackbuffer = false;
		}
		if(backbuffer == null)
		{
			fillFace(hdc);
			drawSecondLabels(hdc);
			drawHourLabels(hdc);
			drawOutline(hdc);
			backbufferBitmap(hdc);
		}else{
			copyBitmap(hdc);
		}
	}
	/*
	 * The backbuffer regeneration function
	 */
	void redoBackBuffer()
	{
		redoBackbuffer = true;
	}
	/*
	 * Draws an outline of the clock face which can be a different color from the clock's filled area 
	 */
	void drawOutline(HDC hdc, COLORREF color = colors.Black, int penwidth = 1, int penstyle = PS_SOLID)
	{
		startPen(hdc, penstyle, penwidth, color);
		foreach(i; 0 .. maxangle)
		{
			auto torad = degToRad(-i);
			auto xy = getXY(torad, radius, center.x, center.y);
			if(i == 0) {
				MoveToEx(hdc, xy.x, xy.y, null);
			}else{
				LineTo(hdc, xy.x, xy.y);
			}
		}
		endPen();
	}
	/*
	 * Fills the clock face with a color;  rather than fill a drawn circle based on sin(),cos(), instead use the Ellipse() winapi;  this is convenient for our purpose
	 */
	void fillFace(HDC hdc, COLORREF color = colors.DarkGray)
	{
		SelectObject(hdc, GetStockObject(DC_BRUSH));
		SetDCBrushColor(hdc, color);
		Ellipse(hdc, left, top, right, bottom);
	}
	/*
	 * The Point at the center of the clock is 1 pixel;  to make the drawing look more like a real-clock, paint a filled ellipse at that location
	 */
	void drawFilledCenter(HDC hdc, COLORREF color = colors.Goldenrod)
	{
		SelectObject(hdc, GetStockObject(DC_BRUSH));
		SetDCBrushColor(hdc, color);
		auto adjust = to!int(0.04 * radius);
		if(adjust >= 4) adjust = 4;
		Ellipse(hdc, center.x-adjust, center.y-adjust, center.x+adjust, center.y+adjust);
	}
	/*
	 * Draw the hour labels (markers) 
	 */
	void drawHourLabels(HDC hdc, COLORREF color = colors.Pink, int penwidth = 1, int penstyle = PS_SOLID)
	{
		startPen(hdc, penstyle, penwidth, color);
		MoveToEx(hdc, center.x, center.y, null);
		auto adjust = 0.2 * radius;
		foreach(i; 0 .. maxangle)
		{
			if(i % anglesInHour == 0)
			{
				auto torad = degToRad(-i);
				auto xystart = getXY(torad, iradius-adjust, center.x, center.y);
				auto xyend = getXY(torad, iradius, center.x, center.y);
				MoveToEx(hdc, xystart.x, xystart.y, null);
				LineTo(hdc, xyend.x, xyend.y);
			}
		}
		endPen();
	}
	/*
	 * Draw the second labels (markers)
	 */
	void drawSecondLabels(HDC hdc, COLORREF color = colors.Gray, int penwidth = 1, int penstyle = PS_SOLID)
	{
		startPen(hdc, penstyle, penwidth, color);
		MoveToEx(hdc, center.x, center.y, null);
		auto adjust = 0.06 * radius;
		foreach(i; 0 .. maxangle)
		{
			if(i % anglesInSecond == 0)
			{
				auto torad = degToRad(-i);
				auto xystart = getXY(torad, iradius-adjust, center.x, center.y);
				auto xyend = getXY(torad, iradius, center.x, center.y);
				MoveToEx(hdc, xystart.x, xystart.y, null);
				LineTo(hdc, xyend.x, xyend.y);
			}
		}
		endPen();
	}
	/*
	 * Draw the HOUR hand
	 */
	void drawHourHand(HDC hdc, int penwidth = 1, COLORREF color = colors.Teal, int penstyle = PS_SOLID)
	{
		startPen(hdc, penstyle, penwidth, color);
		MoveToEx(hdc, center.x, center.y, null);
		auto accum = getTime(byType.Minute) * angleMinute;
		auto hour = getTime(byType.Hour);
		if(hour > 12) {
			hour -= 12;
		}
		auto hand = hour * anglesInHour + anglesDirection;
		auto torad = degToRad(hand+to!int(accum));
		auto adjust = 0.3 * iradius;
		auto xy = getXY(torad, iradius-adjust, center.x, center.y);
		LineTo(hdc, xy.x, xy.y);
		endPen();
	}
	/*
	 * Draw rhe MINUTE hand 
	 */
	void drawMinuteHand(HDC hdc, int penwidth = 1, COLORREF color = colors.Purple, int penstyle = PS_SOLID)
	{
		startPen(hdc, penstyle, penwidth, color);
		MoveToEx(hdc, center.x, center.y, null);
		auto hand = getTime(byType.Minute) * anglesInMinute + anglesDirection;
		auto torad = degToRad(hand);
		auto adjust = 0.1 * iradius;
		auto xy = getXY(torad, iradius-adjust, center.x, center.y);
		LineTo(hdc, xy.x, xy.y);
		endPen();
	}
	/*
	 * Draw the SECONDS hand 
	 */
	void drawSecondHand(HDC hdc, int penwidth = 1, COLORREF color = colors.Goldenrod, int penstyle = PS_SOLID)
	{
		startPen(hdc, penstyle, penwidth, color);
		MoveToEx(hdc, center.x, center.y, null);
		auto hand = getTime(byType.Second) * anglesInSecond + anglesDirection;
		auto torad = degToRad(hand);
		auto xy = getXY(torad, iradius, center.x, center.y);
		LineTo(hdc, xy.x, xy.y);
		MoveToEx(hdc, center.x, center.y, null);
		hand = getTime(byType.Second) * anglesInSecond + -270;
		torad = degToRad(hand);
		auto adjust = 0.7 * iradius;
		xy = getXY(torad, iradius-adjust, center.x, center.y);
		LineTo(hdc, xy.x, xy.y);
		endPen();
	}
	/*
	 * Draw the Time in Textual representation;
	 * The 24/12 cock configurtation is used here to show the time in either format
	 */
	void drawTextTime(HDC hdc, COLORREF color = colors.Crimson)
	{
		auto hour = getTime(byType.Hour);
		if(!display24HourSpec && hour > 12) {
			hour -= 12; 
		}
		string shour;
		string sminute;
		string ssecond;
		immutable int lz = 10;
		if(hour < lz)
		{
			shour = "0" ~ to!string(hour);
		}else{
			shour  = to!string(hour);
		}
		auto minute = getTime(byType.Minute);
		if(minute < lz)
		{
			sminute = "0" ~ to!string(minute);
		}else{
			sminute = to!string(minute);
		}
		auto second = getTime(byType.Second);
		if(second < lz)
		{
			ssecond = "0" ~ to!string(second);
		}else{
			ssecond = to!string(second);
		}
		SetTextColor(hdc, color);
		SetBkColor(hdc, GetSysColor(COLOR_WINDOW+10));
		auto s = shour ~ ":" ~ sminute ~ ":" ~ ssecond;
		auto r = getTextTimeRect();
		DrawText(hdc, toUTFz!(wchar*)(s), -1, &r, DT_LEFT|DT_CENTER);
	}
	/*
	 * Determines if the area of the clock was clicked;  this uses the Region variable and the winapi call to PtInRegion();  returns true if clicked
	 */
	final bool clockClicked(int x, int y)
	{
		return to!bool(PtInRegion(region, x, y));
	}
	/*
	 * Toggles the 24/12 hour display
	 */
	void toggleHourSpec()
	{
		display24HourSpec = !display24HourSpec;
	}
}
