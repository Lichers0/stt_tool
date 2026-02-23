"use client"

import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { MainView, type AppState, type Engine } from "./main-view"
import { HistoryView, type HistoryRecord } from "./history-view"
import { SettingsView } from "./settings-view"
import { PermissionsScreen, defaultPermissions } from "./permissions-screen"

type PopoverTab = "main" | "history" | "settings"

interface PopoverShellProps {
  activeTab: PopoverTab
  onTabChange: (tab: PopoverTab) => void
  showPermissions: boolean
  // Permissions
  permissionsState: typeof defaultPermissions
  onGrantPermission: (id: string) => void
  onPermissionsContinue: () => void
  // Main
  appState: AppState
  engine: Engine
  whisperModel: string
  lastTranscription: { text: string; language: string } | null
  errorMessage: string
  onToggleRecording: () => void
  onOpenVocabManager: () => void
  onQuit: () => void
  onCopyTranscription: () => void
  // History
  historyRecords: HistoryRecord[]
  onCopyRecord: (id: string) => void
  onDeleteRecord: (id: string) => void
  onClearHistory: () => void
  // Settings
  deepgramMode: "streaming" | "rest"
  onDeepgramModeChange: (mode: "streaming" | "rest") => void
  onEngineChange: (engine: Engine) => void
  onWhisperModelChange: (model: string) => void
  apiKey: string
  onApiKeyChange: (key: string) => void
  settingsPermissions: { microphone: boolean; accessibility: boolean }
  onRefreshPermissions: () => void
  onGrantSettingsPermission: (id: string) => void
}

export function PopoverShell(props: PopoverShellProps) {
  if (props.showPermissions) {
    return (
      <div className="w-[360px] overflow-hidden rounded-2xl border border-border/50 bg-popover/95 backdrop-blur-2xl shadow-2xl shadow-black/20">
        <PermissionsScreen
          permissions={props.permissionsState}
          onGrantPermission={props.onGrantPermission}
          onContinue={props.onPermissionsContinue}
        />
      </div>
    )
  }

  return (
    <div className="w-[360px] overflow-hidden rounded-2xl border border-border/50 bg-popover/95 backdrop-blur-2xl shadow-2xl shadow-black/20">
      <Tabs
        value={props.activeTab}
        onValueChange={(v) => props.onTabChange(v as PopoverTab)}
        className="flex flex-col"
      >
        {/* Navigation */}
        <div className="px-3 pt-3 pb-0">
          <TabsList className="w-full h-8 bg-muted/60 p-0.5 rounded-xl">
            <TabsTrigger
              value="main"
              className="flex-1 text-xs h-[calc(100%-2px)] rounded-[10px] data-[state=active]:bg-background data-[state=active]:shadow-sm"
            >
              Main
            </TabsTrigger>
            <TabsTrigger
              value="history"
              className="flex-1 text-xs h-[calc(100%-2px)] rounded-[10px] data-[state=active]:bg-background data-[state=active]:shadow-sm"
            >
              History
            </TabsTrigger>
            <TabsTrigger
              value="settings"
              className="flex-1 text-xs h-[calc(100%-2px)] rounded-[10px] data-[state=active]:bg-background data-[state=active]:shadow-sm"
            >
              Settings
            </TabsTrigger>
          </TabsList>
        </div>

        {/* Content */}
        <TabsContent value="main" className="mt-0">
          <MainView
            appState={props.appState}
            engine={props.engine}
            whisperModel={props.whisperModel}
            lastTranscription={props.lastTranscription}
            errorMessage={props.errorMessage}
            onToggleRecording={props.onToggleRecording}
            onOpenVocabManager={props.onOpenVocabManager}
            onQuit={props.onQuit}
            onCopyTranscription={props.onCopyTranscription}
          />
        </TabsContent>

        <TabsContent value="history" className="mt-0">
          <HistoryView
            records={props.historyRecords}
            onCopy={props.onCopyRecord}
            onDelete={props.onDeleteRecord}
            onClearAll={props.onClearHistory}
          />
        </TabsContent>

        <TabsContent value="settings" className="mt-0">
          <SettingsView
            engine={props.engine}
            onEngineChange={props.onEngineChange}
            deepgramMode={props.deepgramMode}
            onDeepgramModeChange={props.onDeepgramModeChange}
            whisperModel={props.whisperModel}
            onWhisperModelChange={props.onWhisperModelChange}
            apiKey={props.apiKey}
            onApiKeyChange={props.onApiKeyChange}
            onOpenVocabManager={props.onOpenVocabManager}
            permissions={props.settingsPermissions}
            onRefreshPermissions={props.onRefreshPermissions}
            onGrantPermission={props.onGrantSettingsPermission}
          />
        </TabsContent>
      </Tabs>
    </div>
  )
}
