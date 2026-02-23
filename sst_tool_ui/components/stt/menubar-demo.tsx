"use client"

import { useState, useEffect } from "react"
import {
  Mic, Wifi, Battery, Volume2, Search,
} from "lucide-react"
import { cn } from "@/lib/utils"

interface MenuBarDemoProps {
  appState: "idle" | "recording" | "streaming" | "transcribing" | "inserting" | "error"
  popoverOpen: boolean
  onTogglePopover: () => void
  children: React.ReactNode
  overlayContent?: React.ReactNode
}

function Clock() {
  const [time, setTime] = useState("")

  useEffect(() => {
    const update = () => {
      const now = new Date()
      setTime(
        now.toLocaleTimeString("en-US", {
          hour: "numeric",
          minute: "2-digit",
          weekday: "short",
          month: "short",
          day: "numeric",
        })
      )
    }
    update()
    const interval = setInterval(update, 1000)
    return () => clearInterval(interval)
  }, [])

  return <span className="text-xs font-medium text-foreground/90">{time}</span>
}

export function MenuBarDemo({
  appState,
  popoverOpen,
  onTogglePopover,
  children,
  overlayContent,
}: MenuBarDemoProps) {
  const isRecording = appState === "recording" || appState === "streaming"

  return (
    <div className="relative flex h-screen w-full flex-col overflow-hidden bg-background">
      {/* Desktop Wallpaper */}
      <div className="absolute inset-0 bg-gradient-to-br from-blue-900/20 via-indigo-900/10 to-slate-900/20 dark:from-blue-950/40 dark:via-indigo-950/30 dark:to-slate-950/40" />
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-sky-200/10 via-transparent to-transparent dark:from-sky-800/10" />

      {/* Menu Bar */}
      <header className="relative z-50 flex h-7 items-center justify-between border-b border-border/30 bg-background/80 backdrop-blur-2xl px-4">
        {/* Left side */}
        <div className="flex items-center gap-4">
          <svg className="h-3.5 w-3.5 text-foreground/80" viewBox="0 0 24 24" fill="currentColor"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          <span className="text-xs font-semibold text-foreground/90">Finder</span>
          <nav className="flex items-center gap-3">
            {["File", "Edit", "View", "Go", "Window", "Help"].map((item) => (
              <span key={item} className="text-xs text-foreground/60 cursor-default">
                {item}
              </span>
            ))}
          </nav>
        </div>

        {/* Right side (system tray) */}
        <div className="flex items-center gap-3">
          <Volume2 className="h-3.5 w-3.5 text-foreground/60" />
          <Wifi className="h-3.5 w-3.5 text-foreground/60" />
          <Battery className="h-3.5 w-3.5 text-foreground/60" />

          {/* STT Tool icon */}
          <button
            onClick={onTogglePopover}
            className={cn(
              "relative flex h-5 w-5 items-center justify-center rounded-sm transition-colors",
              popoverOpen
                ? "bg-foreground/10"
                : "hover:bg-foreground/5"
            )}
            aria-label="Toggle STT Tool"
          >
            <Mic
              className={cn(
                "h-3.5 w-3.5 transition-colors",
                isRecording
                  ? "text-red-500 animate-pulse-recording"
                  : appState === "transcribing"
                    ? "text-amber-500"
                    : "text-foreground/70"
              )}
            />
            {isRecording && (
              <span className="absolute -top-0.5 -right-0.5 h-1.5 w-1.5 rounded-full bg-red-500" />
            )}
          </button>

          <Search className="h-3.5 w-3.5 text-foreground/60" />
          <Clock />
        </div>
      </header>

      {/* Desktop area */}
      <main className="relative flex-1">
        {/* Popover */}
        {popoverOpen && (
          <>
            {/* Backdrop */}
            <div
              className="fixed inset-0 z-40"
              onClick={onTogglePopover}
            />
            {/* Popover positioned below menubar, near the mic icon */}
            <div className="absolute right-16 top-2 z-50">
              {/* Arrow */}
              <div className="absolute -top-1.5 right-6 h-3 w-3 rotate-45 rounded-sm border-l border-t border-border/50 bg-popover/95 backdrop-blur-2xl" />
              {children}
            </div>
          </>
        )}

        {/* Floating Overlay */}
        {overlayContent && (
          <div className="absolute bottom-8 left-1/2 z-30 -translate-x-1/2">
            {overlayContent}
          </div>
        )}
      </main>
    </div>
  )
}
