"use client"

import { useState, useEffect, useRef } from "react"
import { ScrollArea } from "@/components/ui/scroll-area"
import { cn } from "@/lib/utils"

interface FloatingOverlayProps {
  visible: boolean
  mode: "upper" | "continue"
  vocabularyName: string
  finalText: string
  interimText: string
  isReconnecting?: boolean
}

function Timer() {
  const [seconds, setSeconds] = useState(0)
  const startRef = useRef(Date.now())

  useEffect(() => {
    startRef.current = Date.now()
    setSeconds(0)
    const interval = setInterval(() => {
      setSeconds(Math.floor((Date.now() - startRef.current) / 1000))
    }, 1000)
    return () => clearInterval(interval)
  }, [])

  const mm = String(Math.floor(seconds / 60)).padStart(2, "0")
  const ss = String(seconds % 60).padStart(2, "0")

  return (
    <span className="font-mono text-xs text-foreground/70 tabular-nums">
      {mm}:{ss}
    </span>
  )
}

export function FloatingOverlay({
  visible,
  mode,
  vocabularyName,
  finalText,
  interimText,
  isReconnecting = false,
}: FloatingOverlayProps) {
  if (!visible) return null

  return (
    <div
      className={cn(
        "w-[400px] overflow-hidden rounded-2xl border border-border/30",
        "bg-popover/90 backdrop-blur-2xl shadow-2xl shadow-black/30",
        "transition-opacity duration-200",
        visible ? "opacity-100" : "opacity-0"
      )}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-2.5 border-b border-border/20">
        <div className="flex items-center gap-2.5">
          <span
            className={cn(
              "flex h-5 w-5 items-center justify-center rounded-md text-[10px] font-bold",
              mode === "upper"
                ? "bg-primary/15 text-primary"
                : "bg-amber-500/15 text-amber-500"
            )}
          >
            {mode === "upper" ? "A" : "a"}
          </span>
          <span
            className={cn(
              "text-xs font-medium text-foreground/80",
              isReconnecting && "animate-blink"
            )}
          >
            {vocabularyName}
          </span>
        </div>
        <Timer />
      </div>

      {/* Transcription area */}
      <ScrollArea className="max-h-[250px]">
        <div className="px-4 py-3 min-h-[60px]">
          <p className="text-sm text-foreground leading-relaxed">
            {finalText}
            {interimText && (
              <span className="text-muted-foreground">{interimText}</span>
            )}
            {!finalText && !interimText && (
              <span className="text-muted-foreground/50 italic text-xs">
                Listening...
              </span>
            )}
          </p>
        </div>
      </ScrollArea>
    </div>
  )
}
