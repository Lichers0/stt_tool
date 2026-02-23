"use client"

import { useState } from "react"
import {
  Monitor, Moon, Sun, CheckCircle2, XCircle,
  Eye, EyeOff, BookOpen, RefreshCw, RotateCcw,
} from "lucide-react"
import { useTheme } from "next-themes"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { ScrollArea } from "@/components/ui/scroll-area"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { cn } from "@/lib/utils"
import type { Engine } from "./main-view"

interface SettingsViewProps {
  engine: Engine
  onEngineChange: (engine: Engine) => void
  deepgramMode: "streaming" | "rest"
  onDeepgramModeChange: (mode: "streaming" | "rest") => void
  whisperModel: string
  onWhisperModelChange: (model: string) => void
  apiKey: string
  onApiKeyChange: (key: string) => void
  onOpenVocabManager: () => void
  permissions: { microphone: boolean; accessibility: boolean }
  onRefreshPermissions: () => void
  onGrantPermission: (id: string) => void
}

const whisperModels = [
  { value: "tiny", label: "tiny", size: "75 MB" },
  { value: "base", label: "base", size: "142 MB" },
  { value: "small", label: "small", size: "466 MB" },
  { value: "medium", label: "medium", size: "1.5 GB" },
  { value: "large-v3", label: "large-v3", size: "3.1 GB" },
  { value: "large-v3_turbo", label: "large-v3 turbo", size: "1.6 GB" },
]

export function SettingsView({
  engine,
  onEngineChange,
  deepgramMode,
  onDeepgramModeChange,
  whisperModel,
  onWhisperModelChange,
  apiKey,
  onApiKeyChange,
  onOpenVocabManager,
  permissions,
  onRefreshPermissions,
  onGrantPermission,
}: SettingsViewProps) {
  const { theme, setTheme } = useTheme()
  const [showApiKey, setShowApiKey] = useState(false)
  const [editingKey, setEditingKey] = useState(false)
  const [keyInput, setKeyInput] = useState("")

  const handleSaveKey = () => {
    onApiKeyChange(keyInput)
    setEditingKey(false)
    setKeyInput("")
  }

  return (
    <Tabs defaultValue="general" className="flex flex-col h-full">
      <div className="px-4 pt-4 pb-2">
        <h3 className="text-sm font-semibold text-foreground mb-3">Settings</h3>
        <TabsList className="w-full h-8">
          <TabsTrigger value="general" className="flex-1 text-xs h-7">General</TabsTrigger>
          <TabsTrigger value="engine" className="flex-1 text-xs h-7">Engine</TabsTrigger>
          <TabsTrigger value="permissions" className="flex-1 text-xs h-7">Permissions</TabsTrigger>
        </TabsList>
      </div>

      <ScrollArea className="flex-1 max-h-[360px]">
        {/* General Tab */}
        <TabsContent value="general" className="px-4 pb-4">
          <div className="flex flex-col gap-5 mt-1">
            {/* Theme */}
            <div className="flex flex-col gap-2">
              <Label className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                Appearance
              </Label>
              <div className="grid grid-cols-3 gap-1.5">
                {[
                  { value: "system", icon: Monitor, label: "System" },
                  { value: "light", icon: Sun, label: "Light" },
                  { value: "dark", icon: Moon, label: "Dark" },
                ].map((t) => (
                  <button
                    key={t.value}
                    onClick={() => setTheme(t.value)}
                    className={cn(
                      "flex flex-col items-center gap-1.5 rounded-xl p-2.5 text-xs transition-all",
                      theme === t.value
                        ? "bg-primary/10 text-primary ring-1 ring-primary/20"
                        : "bg-muted/50 text-muted-foreground hover:bg-muted"
                    )}
                  >
                    <t.icon className="h-4 w-4" />
                    <span className="text-[10px] font-medium">{t.label}</span>
                  </button>
                ))}
              </div>
            </div>

            <Separator />

            {/* Hotkey */}
            <div className="flex flex-col gap-2">
              <Label className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                Hotkey
              </Label>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-1.5">
                  <kbd className="inline-flex h-6 items-center rounded-md bg-muted px-2 text-[10px] font-mono font-medium text-foreground border border-border">
                    {"Cmd"}
                  </kbd>
                  <kbd className="inline-flex h-6 items-center rounded-md bg-muted px-2 text-[10px] font-mono font-medium text-foreground border border-border">
                    {"Shift"}
                  </kbd>
                  <kbd className="inline-flex h-6 items-center rounded-md bg-muted px-2 text-[10px] font-mono font-medium text-foreground border border-border">
                    {"Space"}
                  </kbd>
                </div>
                <Button variant="ghost" size="sm" className="text-xs h-7 px-2 rounded-lg gap-1">
                  <RotateCcw className="h-3 w-3" />
                  Reset
                </Button>
              </div>
            </div>

            <Separator />

            {/* Mode Toggle */}
            <div className="flex flex-col gap-2">
              <Label className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                Mode Toggle Key
              </Label>
              <div className="flex items-center gap-1.5">
                <kbd className="inline-flex h-6 items-center rounded-md bg-muted px-2.5 text-[10px] font-mono font-medium text-foreground border border-border">
                  {"Down Arrow"}
                </kbd>
              </div>
            </div>
          </div>
        </TabsContent>

        {/* Engine Tab */}
        <TabsContent value="engine" className="px-4 pb-4">
          <div className="flex flex-col gap-5 mt-1">
            {/* Engine Picker */}
            <div className="flex flex-col gap-2">
              <Label className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                Transcription Engine
              </Label>
              <div className="grid grid-cols-2 gap-1.5">
                {[
                  { value: "deepgram" as Engine, label: "Deepgram", sub: "online" },
                  { value: "whisperkit" as Engine, label: "WhisperKit", sub: "offline" },
                ].map((e) => (
                  <button
                    key={e.value}
                    onClick={() => onEngineChange(e.value)}
                    className={cn(
                      "flex flex-col items-center gap-0.5 rounded-xl p-3 text-xs transition-all",
                      engine === e.value
                        ? "bg-primary/10 text-primary ring-1 ring-primary/20"
                        : "bg-muted/50 text-muted-foreground hover:bg-muted"
                    )}
                  >
                    <span className="text-xs font-medium">{e.label}</span>
                    <span className="text-[10px] opacity-60">{e.sub}</span>
                  </button>
                ))}
              </div>
            </div>

            <Separator />

            {/* Deepgram specific */}
            {engine === "deepgram" && (
              <>
                {/* Mode */}
                <div className="flex flex-col gap-2">
                  <Label className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                    Mode
                  </Label>
                  <div className="grid grid-cols-2 gap-1.5">
                    {[
                      { value: "streaming" as const, label: "Streaming" },
                      { value: "rest" as const, label: "REST" },
                    ].map((m) => (
                      <button
                        key={m.value}
                        onClick={() => onDeepgramModeChange(m.value)}
                        className={cn(
                          "rounded-xl py-2 px-3 text-xs font-medium transition-all",
                          deepgramMode === m.value
                            ? "bg-primary/10 text-primary ring-1 ring-primary/20"
                            : "bg-muted/50 text-muted-foreground hover:bg-muted"
                        )}
                      >
                        {m.label}
                      </button>
                    ))}
                  </div>
                </div>

                <Separator />

                {/* API Key */}
                <div className="flex flex-col gap-2">
                  <Label className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                    API Key
                  </Label>
                  {apiKey && !editingKey ? (
                    <div className="flex items-center gap-2">
                      <div className="flex-1 flex items-center gap-2 rounded-lg bg-muted/50 px-3 py-2">
                        <span className="text-xs font-mono text-foreground flex-1">
                          {showApiKey ? apiKey : "••••••••••••"}
                        </span>
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          className="h-5 w-5 rounded-md"
                          onClick={() => setShowApiKey(!showApiKey)}
                        >
                          {showApiKey ? (
                            <EyeOff className="h-3 w-3 text-muted-foreground" />
                          ) : (
                            <Eye className="h-3 w-3 text-muted-foreground" />
                          )}
                        </Button>
                      </div>
                      <Button
                        variant="outline"
                        size="sm"
                        className="text-xs h-8 px-2.5 rounded-lg"
                        onClick={() => {
                          setEditingKey(true)
                          setKeyInput(apiKey)
                        }}
                      >
                        Change
                      </Button>
                    </div>
                  ) : (
                    <div className="flex items-center gap-2">
                      <Input
                        type="password"
                        placeholder="Enter API key..."
                        className="flex-1 h-8 text-xs rounded-lg"
                        value={keyInput}
                        onChange={(e) => setKeyInput(e.target.value)}
                      />
                      <Button
                        size="sm"
                        className="text-xs h-8 px-3 rounded-lg"
                        disabled={!keyInput}
                        onClick={handleSaveKey}
                      >
                        Save
                      </Button>
                      {editingKey && (
                        <Button
                          variant="ghost"
                          size="sm"
                          className="text-xs h-8 px-2 rounded-lg"
                          onClick={() => {
                            setEditingKey(false)
                            setKeyInput("")
                          }}
                        >
                          Cancel
                        </Button>
                      )}
                    </div>
                  )}
                </div>

                <Separator />

                {/* Vocabulary */}
                <div className="flex flex-col gap-2">
                  <Label className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                    Vocabulary
                  </Label>
                  <Button
                    variant="outline"
                    size="sm"
                    className="w-full justify-start text-xs h-8 rounded-lg gap-2"
                    onClick={onOpenVocabManager}
                  >
                    <BookOpen className="h-3.5 w-3.5" />
                    Manage Vocabularies...
                  </Button>
                  <p className="text-[10px] text-muted-foreground leading-relaxed">
                    Create themed vocabularies to improve recognition accuracy for specialized terms.
                  </p>
                </div>
              </>
            )}

            {/* WhisperKit specific */}
            {engine === "whisperkit" && (
              <div className="flex flex-col gap-2">
                <Label className="text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                  Model
                </Label>
                <RadioGroup
                  value={whisperModel}
                  onValueChange={onWhisperModelChange}
                  className="gap-1"
                >
                  {whisperModels.map((model) => (
                    <label
                      key={model.value}
                      className={cn(
                        "flex items-center gap-3 rounded-xl px-3 py-2.5 cursor-pointer transition-colors",
                        whisperModel === model.value
                          ? "bg-primary/5"
                          : "hover:bg-muted/50"
                      )}
                    >
                      <RadioGroupItem value={model.value} />
                      <span className="text-xs font-medium text-foreground flex-1">{model.label}</span>
                      <span className="text-[10px] text-muted-foreground">{model.size}</span>
                    </label>
                  ))}
                </RadioGroup>
              </div>
            )}
          </div>
        </TabsContent>

        {/* Permissions Tab */}
        <TabsContent value="permissions" className="px-4 pb-4">
          <div className="flex flex-col gap-3 mt-1">
            {[
              { id: "microphone", label: "Microphone", granted: permissions.microphone },
              { id: "accessibility", label: "Accessibility", granted: permissions.accessibility },
            ].map((perm) => (
              <div
                key={perm.id}
                className={cn(
                  "flex items-center justify-between rounded-xl p-3 transition-colors",
                  perm.granted ? "bg-green-500/5" : "bg-red-500/5"
                )}
              >
                <div className="flex items-center gap-2.5">
                  {perm.granted ? (
                    <CheckCircle2 className="h-4 w-4 text-green-500" />
                  ) : (
                    <XCircle className="h-4 w-4 text-red-500" />
                  )}
                  <span className="text-xs font-medium text-foreground">{perm.label}</span>
                </div>
                {!perm.granted && (
                  <Button
                    variant="outline"
                    size="sm"
                    className="text-xs h-7 px-2.5 rounded-lg"
                    onClick={() => onGrantPermission(perm.id)}
                  >
                    Grant
                  </Button>
                )}
              </div>
            ))}

            <Button
              variant="ghost"
              size="sm"
              className="w-full text-xs h-8 rounded-lg gap-1.5 mt-1"
              onClick={onRefreshPermissions}
            >
              <RefreshCw className="h-3 w-3" />
              Refresh Status
            </Button>
          </div>
        </TabsContent>
      </ScrollArea>
    </Tabs>
  )
}
