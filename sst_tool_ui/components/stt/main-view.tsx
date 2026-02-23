"use client"

import { Mic, Square, Copy, BookOpen, Power } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { cn } from "@/lib/utils"

export type AppState = "idle" | "recording" | "streaming" | "transcribing" | "inserting" | "error"
export type Engine = "deepgram" | "whisperkit"

interface MainViewProps {
  appState: AppState
  engine: Engine
  whisperModel: string
  lastTranscription: { text: string; language: string } | null
  errorMessage: string
  onToggleRecording: () => void
  onOpenVocabManager: () => void
  onQuit: () => void
  onCopyTranscription: () => void
}

const stateConfig: Record<AppState, { label: string; color: string; animate?: boolean }> = {
  idle: { label: "Ready", color: "text-muted-foreground" },
  recording: { label: "Recording...", color: "text-red-500", animate: true },
  streaming: { label: "Recording (streaming)...", color: "text-red-500", animate: true },
  transcribing: { label: "Transcribing...", color: "text-amber-500" },
  inserting: { label: "Inserting text...", color: "text-primary" },
  error: { label: "Error", color: "text-red-500" },
}

export function MainView({
  appState,
  engine,
  whisperModel,
  lastTranscription,
  errorMessage,
  onToggleRecording,
  onOpenVocabManager,
  onQuit,
  onCopyTranscription,
}: MainViewProps) {
  const state = stateConfig[appState]
  const isRecording = appState === "recording" || appState === "streaming"
  const isDisabled = appState === "transcribing" || appState === "inserting"

  return (
    <div className="flex flex-col gap-4 p-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-primary/10">
            <Mic className="h-4 w-4 text-primary" />
          </div>
          <span className="text-sm font-semibold text-foreground">STT Tool</span>
        </div>
        <Badge
          variant="secondary"
          className={cn(
            "rounded-full text-[10px] font-medium px-2.5 py-0.5 border-0",
            engine === "deepgram"
              ? "bg-blue-500/10 text-blue-600 dark:text-blue-400"
              : "bg-green-500/10 text-green-600 dark:text-green-400"
          )}
        >
          {engine === "deepgram" ? "Deepgram" : whisperModel}
        </Badge>
      </div>

      {/* Status */}
      <div className="flex items-center justify-center gap-2 py-1">
        <div
          className={cn(
            "h-1.5 w-1.5 rounded-full",
            appState === "idle" && "bg-muted-foreground/50",
            isRecording && "bg-red-500 animate-pulse-recording",
            appState === "transcribing" && "bg-amber-500",
            appState === "inserting" && "bg-primary",
            appState === "error" && "bg-red-500"
          )}
        />
        <span className={cn("text-xs font-medium", state.color)}>
          {appState === "error" ? `Error: ${errorMessage}` : state.label}
        </span>
      </div>

      {/* Record Button */}
      <Button
        className={cn(
          "w-full rounded-xl h-11 text-sm font-medium transition-all",
          isRecording
            ? "bg-red-500 text-white hover:bg-red-600"
            : "bg-primary text-primary-foreground hover:bg-primary/90"
        )}
        disabled={isDisabled}
        onClick={onToggleRecording}
      >
        {isRecording ? (
          <>
            <Square className="h-4 w-4 fill-current" />
            Stop Recording
          </>
        ) : (
          <>
            <Mic className="h-4 w-4" />
            Start Recording
          </>
        )}
      </Button>

      {/* Last Transcription */}
      {lastTranscription && (
        <div className="rounded-xl bg-muted/50 p-3">
          <div className="flex items-center justify-between mb-2">
            <span className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
              Last transcription
            </span>
            <Button
              variant="ghost"
              size="icon-sm"
              className="h-6 w-6 rounded-lg"
              onClick={onCopyTranscription}
            >
              <Copy className="h-3 w-3 text-muted-foreground" />
            </Button>
          </div>
          <div className="flex items-start gap-2">
            {lastTranscription.language && (
              <Badge variant="outline" className="rounded-md text-[10px] px-1.5 py-0 shrink-0 mt-0.5 border-border">
                {lastTranscription.language}
              </Badge>
            )}
            <p className="text-xs text-foreground leading-relaxed line-clamp-4 select-text">
              {lastTranscription.text}
            </p>
          </div>
        </div>
      )}

      {/* Footer Actions */}
      <Separator />
      <div className="flex items-center justify-between">
        {engine === "deepgram" && (
          <Button
            variant="ghost"
            size="sm"
            className="text-xs text-muted-foreground hover:text-foreground h-7 px-2 rounded-lg gap-1.5"
            onClick={onOpenVocabManager}
          >
            <BookOpen className="h-3.5 w-3.5" />
            Vocabularies
          </Button>
        )}
        {engine !== "deepgram" && <div />}
        <Button
          variant="ghost"
          size="sm"
          className="text-xs text-muted-foreground hover:text-destructive h-7 px-2 rounded-lg gap-1.5"
          onClick={onQuit}
        >
          <Power className="h-3.5 w-3.5" />
          Quit
        </Button>
      </div>
    </div>
  )
}
