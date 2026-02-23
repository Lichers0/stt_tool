"use client"

import { Copy, Trash2, MessageSquare } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"

export interface HistoryRecord {
  id: string
  text: string
  language: string
  model: string
  timestamp: Date
}

interface HistoryViewProps {
  records: HistoryRecord[]
  onCopy: (id: string) => void
  onDelete: (id: string) => void
  onClearAll: () => void
}

function formatRelativeTime(date: Date): string {
  const now = new Date()
  const diff = now.getTime() - date.getTime()
  const minutes = Math.floor(diff / 60000)
  const hours = Math.floor(diff / 3600000)
  const days = Math.floor(diff / 86400000)

  if (minutes < 1) return "just now"
  if (minutes < 60) return `${minutes}m ago`
  if (hours < 24) return `${hours}h ago`
  return `${days}d ago`
}

export function HistoryView({ records, onCopy, onDelete, onClearAll }: HistoryViewProps) {
  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between px-4 pt-4 pb-2">
        <h3 className="text-sm font-semibold text-foreground">History</h3>
        {records.length > 0 && (
          <Button
            variant="ghost"
            size="sm"
            className="text-xs text-destructive hover:text-destructive h-7 px-2 rounded-lg"
            onClick={onClearAll}
          >
            Clear All
          </Button>
        )}
      </div>

      <Separator className="mx-4 w-auto" />

      {/* Content */}
      {records.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-2 py-16 px-4">
          <MessageSquare className="h-8 w-8 text-muted-foreground/30" />
          <span className="text-xs text-muted-foreground">No transcriptions yet</span>
        </div>
      ) : (
        <ScrollArea className="flex-1 max-h-[340px]">
          <div className="flex flex-col">
            {records.map((record, index) => (
              <div key={record.id}>
                <div className="group flex flex-col gap-2 px-4 py-3 hover:bg-muted/30 transition-colors">
                  <p className="text-xs text-foreground leading-relaxed line-clamp-3 select-text">
                    {record.text}
                  </p>
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      {record.language && (
                        <Badge variant="outline" className="rounded-md text-[10px] px-1.5 py-0 border-border">
                          {record.language}
                        </Badge>
                      )}
                      <span className="text-[10px] text-muted-foreground">
                        {formatRelativeTime(record.timestamp)}
                      </span>
                      <span className="text-[10px] text-muted-foreground/60">
                        {record.model}
                      </span>
                    </div>
                    <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        className="h-6 w-6 rounded-lg"
                        onClick={() => onCopy(record.id)}
                      >
                        <Copy className="h-3 w-3 text-muted-foreground" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        className="h-6 w-6 rounded-lg hover:text-destructive"
                        onClick={() => onDelete(record.id)}
                      >
                        <Trash2 className="h-3 w-3 text-muted-foreground" />
                      </Button>
                    </div>
                  </div>
                </div>
                {index < records.length - 1 && <Separator className="mx-4 w-auto" />}
              </div>
            ))}
          </div>
        </ScrollArea>
      )}
    </div>
  )
}
