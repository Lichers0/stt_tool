"use client"

import { useState, useCallback, useEffect, useRef } from "react"
import { MenuBarDemo } from "@/components/stt/menubar-demo"
import { PopoverShell } from "@/components/stt/popover-shell"
import { FloatingOverlay } from "@/components/stt/floating-overlay"
import { VocabularyManager, type Vocabulary } from "@/components/stt/vocabulary-manager"
import { defaultPermissions } from "@/components/stt/permissions-screen"
import type { AppState, Engine } from "@/components/stt/main-view"
import type { HistoryRecord } from "@/components/stt/history-view"

const DEMO_HISTORY: HistoryRecord[] = [
  {
    id: "1",
    text: "The quarterly revenue exceeded expectations with a 15% increase compared to the previous year, driven by strong performance in the enterprise segment.",
    language: "en",
    model: "Deepgram",
    timestamp: new Date(Date.now() - 120000),
  },
  {
    id: "2",
    text: "Please schedule the follow-up meeting with the engineering team for next Thursday at 2 PM Pacific time.",
    language: "en",
    model: "Deepgram",
    timestamp: new Date(Date.now() - 3600000),
  },
  {
    id: "3",
    text: "Necesitamos revisar los resultados del ultimo sprint y planificar las tareas para la proxima iteracion del proyecto.",
    language: "es",
    model: "large-v3",
    timestamp: new Date(Date.now() - 7200000),
  },
]

const DEMO_VOCABULARIES: Vocabulary[] = [
  {
    id: "general",
    name: "General",
    terms: ["hello", "world", "transcription", "speech", "recognition"],
    isActive: true,
  },
  {
    id: "medical",
    name: "Medical",
    terms: ["diagnosis", "prognosis", "hematology", "cardiology", "oncology", "radiology"],
    isActive: false,
  },
  {
    id: "legal",
    name: "Legal",
    terms: ["plaintiff", "defendant", "subpoena", "deposition", "arbitration"],
    isActive: false,
  },
]

const STREAMING_SENTENCES = [
  "The weather today is expected to be partly cloudy ",
  "with temperatures reaching around 72 degrees Fahrenheit. ",
  "Later in the afternoon, there might be a slight chance of rain ",
  "so it would be wise to carry an umbrella just in case.",
]

export default function Page() {
  // Core state
  const [popoverOpen, setPopoverOpen] = useState(true)
  const [showPermissions, setShowPermissions] = useState(false)
  const [activeTab, setActiveTab] = useState<"main" | "history" | "settings">("main")
  const [appState, setAppState] = useState<AppState>("idle")
  const [engine, setEngine] = useState<Engine>("deepgram")
  const [deepgramMode, setDeepgramMode] = useState<"streaming" | "rest">("streaming")
  const [whisperModel, setWhisperModel] = useState("small")
  const [apiKey, setApiKey] = useState("dg_a1b2c3d4e5f6g7h8i9j0")
  const [errorMessage, setErrorMessage] = useState("")

  // Permissions
  const [permissions, setPermissions] = useState(() =>
    defaultPermissions.map((p) => ({ ...p, granted: true }))
  )

  // History
  const [history, setHistory] = useState<HistoryRecord[]>(DEMO_HISTORY)

  // Vocabulary
  const [vocabManagerOpen, setVocabManagerOpen] = useState(false)
  const [vocabularies, setVocabularies] = useState<Vocabulary[]>(DEMO_VOCABULARIES)
  const [defaultVocabMode, setDefaultVocabMode] = useState<"last" | "specific">("last")
  const [defaultVocabId, setDefaultVocabId] = useState<string | null>(null)

  // Last transcription
  const [lastTranscription, setLastTranscription] = useState<{
    text: string
    language: string
  } | null>({
    text: "The quarterly revenue exceeded expectations with a 15% increase compared to the previous year.",
    language: "en",
  })

  // Streaming overlay
  const [overlayMode, setOverlayMode] = useState<"upper" | "continue">("upper")
  const [finalText, setFinalText] = useState("")
  const [interimText, setInterimText] = useState("")
  const streamingRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const sentenceIndexRef = useRef(0)
  const charIndexRef = useRef(0)

  const showOverlay =
    (appState === "streaming" || appState === "recording") &&
    engine === "deepgram" &&
    deepgramMode === "streaming"

  // Simulate streaming transcription
  const startStreamingSimulation = useCallback(() => {
    sentenceIndexRef.current = 0
    charIndexRef.current = 0
    setFinalText("")
    setInterimText("")

    const tick = () => {
      const si = sentenceIndexRef.current
      const ci = charIndexRef.current

      if (si >= STREAMING_SENTENCES.length) {
        // Loop back
        sentenceIndexRef.current = 0
        charIndexRef.current = 0
        setFinalText("")
        setInterimText("")
        streamingRef.current = setTimeout(tick, 500)
        return
      }

      const sentence = STREAMING_SENTENCES[si]
      if (ci < sentence.length) {
        setInterimText(sentence.slice(0, ci + 1))
        charIndexRef.current = ci + 1
        streamingRef.current = setTimeout(tick, 30 + Math.random() * 50)
      } else {
        setFinalText((prev) => prev + sentence)
        setInterimText("")
        sentenceIndexRef.current = si + 1
        charIndexRef.current = 0
        streamingRef.current = setTimeout(tick, 200)
      }
    }

    streamingRef.current = setTimeout(tick, 500)
  }, [])

  const stopStreamingSimulation = useCallback(() => {
    if (streamingRef.current) {
      clearTimeout(streamingRef.current)
      streamingRef.current = null
    }
  }, [])

  // Recording toggle
  const handleToggleRecording = useCallback(() => {
    if (appState === "idle") {
      if (engine === "deepgram" && deepgramMode === "streaming") {
        setAppState("streaming")
        startStreamingSimulation()
      } else {
        setAppState("recording")
      }
    } else if (appState === "recording" || appState === "streaming") {
      stopStreamingSimulation()
      setAppState("transcribing")

      // Simulate transcription delay
      setTimeout(() => {
        setAppState("inserting")
        const newRecord: HistoryRecord = {
          id: crypto.randomUUID(),
          text: finalText + interimText || "This is a simulated transcription result for demo purposes.",
          language: "en",
          model: engine === "deepgram" ? "Deepgram" : whisperModel,
          timestamp: new Date(),
        }
        setLastTranscription({
          text: newRecord.text,
          language: newRecord.language,
        })
        setHistory((prev) => [newRecord, ...prev])

        setTimeout(() => {
          setAppState("idle")
          setFinalText("")
          setInterimText("")
        }, 800)
      }, 1500)
    }
  }, [appState, engine, deepgramMode, whisperModel, finalText, interimText, startStreamingSimulation, stopStreamingSimulation])

  // Cleanup
  useEffect(() => {
    return () => stopStreamingSimulation()
  }, [stopStreamingSimulation])

  // Permission handling
  const handleGrantPermission = useCallback((id: string) => {
    setPermissions((prev) =>
      prev.map((p) => (p.id === id ? { ...p, granted: true } : p))
    )
  }, [])

  // History actions
  const handleCopyRecord = useCallback((id: string) => {
    const record = history.find((r) => r.id === id)
    if (record) {
      navigator.clipboard?.writeText(record.text)
    }
  }, [history])

  const handleDeleteRecord = useCallback((id: string) => {
    setHistory((prev) => prev.filter((r) => r.id !== id))
  }, [])

  const handleClearHistory = useCallback(() => {
    setHistory([])
  }, [])

  const handleCopyTranscription = useCallback(() => {
    if (lastTranscription) {
      navigator.clipboard?.writeText(lastTranscription.text)
    }
  }, [lastTranscription])

  const activeVocab = vocabularies.find((v) => v.isActive)

  return (
    <MenuBarDemo
      appState={appState}
      popoverOpen={popoverOpen}
      onTogglePopover={() => setPopoverOpen(!popoverOpen)}
      overlayContent={
        showOverlay ? (
          <FloatingOverlay
            visible
            mode={overlayMode}
            vocabularyName={activeVocab?.name ?? "General"}
            finalText={finalText}
            interimText={interimText}
          />
        ) : undefined
      }
    >
      <PopoverShell
        activeTab={activeTab}
        onTabChange={setActiveTab}
        showPermissions={showPermissions}
        permissionsState={permissions}
        onGrantPermission={handleGrantPermission}
        onPermissionsContinue={() => setShowPermissions(false)}
        appState={appState}
        engine={engine}
        whisperModel={whisperModel}
        lastTranscription={lastTranscription}
        errorMessage={errorMessage}
        onToggleRecording={handleToggleRecording}
        onOpenVocabManager={() => setVocabManagerOpen(true)}
        onQuit={() => {
          setPopoverOpen(false)
          setAppState("idle")
          stopStreamingSimulation()
        }}
        onCopyTranscription={handleCopyTranscription}
        historyRecords={history}
        onCopyRecord={handleCopyRecord}
        onDeleteRecord={handleDeleteRecord}
        onClearHistory={handleClearHistory}
        deepgramMode={deepgramMode}
        onDeepgramModeChange={setDeepgramMode}
        onEngineChange={setEngine}
        onWhisperModelChange={setWhisperModel}
        apiKey={apiKey}
        onApiKeyChange={setApiKey}
        settingsPermissions={{
          microphone: permissions.find((p) => p.id === "microphone")?.granted ?? false,
          accessibility: permissions.find((p) => p.id === "accessibility")?.granted ?? false,
        }}
        onRefreshPermissions={() => {
          // Simulate refresh
        }}
        onGrantSettingsPermission={handleGrantPermission}
      />

      <VocabularyManager
        open={vocabManagerOpen}
        onOpenChange={setVocabManagerOpen}
        vocabularies={vocabularies}
        onVocabulariesChange={setVocabularies}
        defaultMode={defaultVocabMode}
        onDefaultModeChange={setDefaultVocabMode}
        defaultVocabularyId={defaultVocabId}
        onDefaultVocabularyIdChange={setDefaultVocabId}
      />
    </MenuBarDemo>
  )
}
