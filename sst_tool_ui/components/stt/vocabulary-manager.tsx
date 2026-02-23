"use client"

import { useState, useCallback } from "react"
import {
  Plus, Copy, Pencil, Trash2, X, Check,
  CheckSquare, Square, ArrowRightLeft, ClipboardCopy,
  MoreHorizontal,
} from "lucide-react"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import { Checkbox } from "@/components/ui/checkbox"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import {
  ResizablePanelGroup,
  ResizablePanel,
  ResizableHandle,
} from "@/components/ui/resizable"
import { cn } from "@/lib/utils"

export interface Vocabulary {
  id: string
  name: string
  terms: string[]
  isActive: boolean
}

interface VocabularyManagerProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  vocabularies: Vocabulary[]
  onVocabulariesChange: (vocabularies: Vocabulary[]) => void
  defaultMode: "last" | "specific"
  onDefaultModeChange: (mode: "last" | "specific") => void
  defaultVocabularyId: string | null
  onDefaultVocabularyIdChange: (id: string | null) => void
}

const MAX_TERMS = 100

export function VocabularyManager({
  open,
  onOpenChange,
  vocabularies,
  onVocabulariesChange,
  defaultMode,
  onDefaultModeChange,
  defaultVocabularyId,
  onDefaultVocabularyIdChange,
}: VocabularyManagerProps) {
  const [selectedId, setSelectedId] = useState<string | null>(
    vocabularies[0]?.id ?? null
  )
  const [newTerm, setNewTerm] = useState("")
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editingName, setEditingName] = useState("")
  const [selectedTerms, setSelectedTerms] = useState<Set<string>>(new Set())
  const [selectionMode, setSelectionMode] = useState(false)

  const selected = vocabularies.find((v) => v.id === selectedId)

  const toggleTermSelection = useCallback((term: string) => {
    setSelectedTerms((prev) => {
      const next = new Set(prev)
      if (next.has(term)) next.delete(term)
      else next.add(term)
      return next
    })
  }, [])

  const selectAllTerms = useCallback(() => {
    if (!selected) return
    setSelectedTerms(new Set(selected.terms))
  }, [selected])

  const deselectAllTerms = useCallback(() => {
    setSelectedTerms(new Set())
  }, [])

  const exitSelectionMode = useCallback(() => {
    setSelectionMode(false)
    setSelectedTerms(new Set())
  }, [])

  const handleCopyToVocabulary = useCallback(
    (targetId: string) => {
      if (!selected || selectedTerms.size === 0) return
      const target = vocabularies.find((v) => v.id === targetId)
      if (!target) return
      const existingSet = new Set(target.terms)
      const newTerms = Array.from(selectedTerms).filter((t) => !existingSet.has(t))
      if (newTerms.length === 0) return
      onVocabulariesChange(
        vocabularies.map((v) =>
          v.id === targetId
            ? { ...v, terms: [...v.terms, ...newTerms].slice(0, MAX_TERMS) }
            : v
        )
      )
      exitSelectionMode()
    },
    [selected, selectedTerms, vocabularies, onVocabulariesChange, exitSelectionMode]
  )

  const handleMoveToVocabulary = useCallback(
    (targetId: string) => {
      if (!selected || selectedTerms.size === 0) return
      const target = vocabularies.find((v) => v.id === targetId)
      if (!target) return
      const existingSet = new Set(target.terms)
      const termsToMove = Array.from(selectedTerms)
      const newTargetTerms = [
        ...target.terms,
        ...termsToMove.filter((t) => !existingSet.has(t)),
      ].slice(0, MAX_TERMS)
      const remainingTerms = selected.terms.filter((t) => !selectedTerms.has(t))
      onVocabulariesChange(
        vocabularies.map((v) => {
          if (v.id === targetId) return { ...v, terms: newTargetTerms }
          if (v.id === selected.id) return { ...v, terms: remainingTerms }
          return v
        })
      )
      exitSelectionMode()
    },
    [selected, selectedTerms, vocabularies, onVocabulariesChange, exitSelectionMode]
  )

  const handleDeleteSelected = useCallback(() => {
    if (!selected || selectedTerms.size === 0) return
    onVocabulariesChange(
      vocabularies.map((v) =>
        v.id === selected.id
          ? { ...v, terms: v.terms.filter((t) => !selectedTerms.has(t)) }
          : v
      )
    )
    exitSelectionMode()
  }, [selected, selectedTerms, vocabularies, onVocabulariesChange, exitSelectionMode])

  const handleAddVocabulary = () => {
    const newVocab: Vocabulary = {
      id: crypto.randomUUID(),
      name: "New Vocabulary",
      terms: [],
      isActive: false,
    }
    onVocabulariesChange([...vocabularies, newVocab])
    setSelectedId(newVocab.id)
    setEditingId(newVocab.id)
    setEditingName(newVocab.name)
  }

  const handleDuplicate = () => {
    if (!selected) return
    const dup: Vocabulary = {
      id: crypto.randomUUID(),
      name: `${selected.name} (Copy)`,
      terms: [...selected.terms],
      isActive: false,
    }
    onVocabulariesChange([...vocabularies, dup])
    setSelectedId(dup.id)
  }

  const handleDelete = () => {
    if (!selected || vocabularies.length <= 1) return
    const updated = vocabularies.filter((v) => v.id !== selected.id)
    onVocabulariesChange(updated)
    setSelectedId(updated[0]?.id ?? null)
  }

  const handleRename = (id: string) => {
    setEditingId(id)
    const vocab = vocabularies.find((v) => v.id === id)
    setEditingName(vocab?.name ?? "")
  }

  const handleSaveRename = () => {
    if (!editingId || !editingName.trim()) return
    onVocabulariesChange(
      vocabularies.map((v) =>
        v.id === editingId ? { ...v, name: editingName.trim() } : v
      )
    )
    setEditingId(null)
    setEditingName("")
  }

  const handleAddTerm = () => {
    if (!selected || !newTerm.trim() || selected.terms.length >= MAX_TERMS) return
    if (selected.terms.includes(newTerm.trim())) return
    onVocabulariesChange(
      vocabularies.map((v) =>
        v.id === selected.id
          ? { ...v, terms: [...v.terms, newTerm.trim()] }
          : v
      )
    )
    setNewTerm("")
  }

  const handleRemoveTerm = (term: string) => {
    if (!selected) return
    onVocabulariesChange(
      vocabularies.map((v) =>
        v.id === selected.id
          ? { ...v, terms: v.terms.filter((t) => t !== term) }
          : v
      )
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[680px] p-0 gap-0 rounded-2xl overflow-hidden" showCloseButton={false}>
        <DialogHeader className="px-4 pt-4 pb-3">
          <div className="flex items-center justify-between">
            <div>
              <DialogTitle className="text-sm font-semibold">Vocabulary Manager</DialogTitle>
              <DialogDescription className="sr-only">Manage custom vocabulary words and phrases for speech recognition</DialogDescription>
            </div>
            <Button
              variant="ghost"
              size="icon-sm"
              className="h-6 w-6 rounded-lg"
              onClick={() => onOpenChange(false)}
            >
              <X className="h-3.5 w-3.5" />
            </Button>
          </div>
        </DialogHeader>

        <Separator />

        <ResizablePanelGroup direction="horizontal" className="min-h-[380px]">
          {/* Sidebar */}
          <ResizablePanel defaultSize={35} minSize={25}>
            <div className="flex h-full flex-col">
              <ScrollArea className="flex-1">
                <div className="flex flex-col py-1">
                  {vocabularies.map((vocab) => (
                    <div
                      key={vocab.id}
                      role="button"
                      tabIndex={0}
                      onClick={() => {
                        setSelectedId(vocab.id)
                        exitSelectionMode()
                      }}
                      onDoubleClick={() => handleRename(vocab.id)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") setSelectedId(vocab.id)
                      }}
                      className={cn(
                        "flex items-center gap-2 px-3 py-2 text-left transition-colors cursor-pointer",
                        selectedId === vocab.id
                          ? "bg-primary/10 text-primary"
                          : "text-foreground hover:bg-muted/50"
                      )}
                    >
                      {vocab.isActive && (
                        <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-primary" />
                      )}
                      {editingId === vocab.id ? (
                        <div className="flex items-center gap-1 flex-1">
                          <Input
                            value={editingName}
                            onChange={(e) => setEditingName(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === "Enter") handleSaveRename()
                              if (e.key === "Escape") setEditingId(null)
                            }}
                            className="h-6 text-xs px-1.5 rounded-md flex-1"
                            autoFocus
                          />
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            className="h-5 w-5 rounded-md shrink-0"
                            onClick={(e) => {
                              e.stopPropagation()
                              handleSaveRename()
                            }}
                          >
                            <Check className="h-3 w-3" />
                          </Button>
                        </div>
                      ) : (
                        <div className="flex items-center justify-between flex-1 min-w-0">
                          <span className="text-xs font-medium truncate">{vocab.name}</span>
                          <span className="text-[10px] text-muted-foreground shrink-0 ml-2">
                            {vocab.terms.length}
                          </span>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </ScrollArea>

              <Separator />

              {/* Sidebar toolbar */}
              <div className="flex items-center justify-between px-2 py-1.5">
                <div className="flex items-center gap-0.5">
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    className="h-7 w-7 rounded-lg"
                    onClick={handleAddVocabulary}
                  >
                    <Plus className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    className="h-7 w-7 rounded-lg"
                    disabled={!selected}
                    onClick={handleDuplicate}
                  >
                    <Copy className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    className="h-7 w-7 rounded-lg"
                    disabled={!selected}
                    onClick={() => selected && handleRename(selected.id)}
                  >
                    <Pencil className="h-3.5 w-3.5" />
                  </Button>
                </div>
                <Button
                  variant="ghost"
                  size="icon-sm"
                  className="h-7 w-7 rounded-lg hover:text-destructive"
                  disabled={!selected || vocabularies.length <= 1}
                  onClick={handleDelete}
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </Button>
              </div>
            </div>
          </ResizablePanel>

          <ResizableHandle />

          {/* Detail Panel */}
          <ResizablePanel defaultSize={65}>
            {selected ? (
              <div className="flex h-full flex-col">
                {/* Header with title and actions */}
                <div className="flex items-center justify-between px-4 py-3">
                  <h4 className="text-sm font-semibold text-foreground">{selected.name}</h4>
                  {selected.terms.length > 0 && (
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-7 rounded-lg text-[11px] gap-1.5"
                      onClick={() => {
                        if (selectionMode) exitSelectionMode()
                        else setSelectionMode(true)
                      }}
                    >
                      {selectionMode ? (
                        <>
                          <X className="h-3 w-3" />
                          Cancel
                        </>
                      ) : (
                        <>
                          <CheckSquare className="h-3 w-3" />
                          Select
                        </>
                      )}
                    </Button>
                  )}
                </div>

                <Separator />

                {/* Selection toolbar - shown when in selection mode */}
                {selectionMode && (
                  <>
                    <div className="flex items-center justify-between px-4 py-2 bg-muted/30">
                      <div className="flex items-center gap-2">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-6 rounded-md text-[10px] gap-1"
                          onClick={
                            selectedTerms.size === selected.terms.length
                              ? deselectAllTerms
                              : selectAllTerms
                          }
                        >
                          {selectedTerms.size === selected.terms.length ? (
                            <>
                              <Square className="h-3 w-3" />
                              Deselect all
                            </>
                          ) : (
                            <>
                              <CheckSquare className="h-3 w-3" />
                              Select all
                            </>
                          )}
                        </Button>
                        {selectedTerms.size > 0 && (
                          <span className="text-[10px] text-muted-foreground">
                            {selectedTerms.size} selected
                          </span>
                        )}
                      </div>

                      {selectedTerms.size > 0 && (
                        <div className="flex items-center gap-1">
                          {/* Copy to... */}
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button
                                variant="ghost"
                                size="sm"
                                className="h-6 rounded-md text-[10px] gap-1"
                              >
                                <ClipboardCopy className="h-3 w-3" />
                                Copy to
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end" className="min-w-[160px]">
                              {vocabularies
                                .filter((v) => v.id !== selected.id)
                                .map((v) => (
                                  <DropdownMenuItem
                                    key={v.id}
                                    onClick={() => handleCopyToVocabulary(v.id)}
                                    className="text-xs"
                                  >
                                    {v.name}
                                  </DropdownMenuItem>
                                ))}
                              {vocabularies.filter((v) => v.id !== selected.id).length === 0 && (
                                <DropdownMenuItem disabled className="text-xs text-muted-foreground">
                                  No other vocabularies
                                </DropdownMenuItem>
                              )}
                            </DropdownMenuContent>
                          </DropdownMenu>

                          {/* Move to... */}
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button
                                variant="ghost"
                                size="sm"
                                className="h-6 rounded-md text-[10px] gap-1"
                              >
                                <ArrowRightLeft className="h-3 w-3" />
                                Move to
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end" className="min-w-[160px]">
                              {vocabularies
                                .filter((v) => v.id !== selected.id)
                                .map((v) => (
                                  <DropdownMenuItem
                                    key={v.id}
                                    onClick={() => handleMoveToVocabulary(v.id)}
                                    className="text-xs"
                                  >
                                    {v.name}
                                  </DropdownMenuItem>
                                ))}
                              {vocabularies.filter((v) => v.id !== selected.id).length === 0 && (
                                <DropdownMenuItem disabled className="text-xs text-muted-foreground">
                                  No other vocabularies
                                </DropdownMenuItem>
                              )}
                            </DropdownMenuContent>
                          </DropdownMenu>

                          {/* Delete selected */}
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            className="h-6 w-6 rounded-md hover:text-destructive"
                            onClick={handleDeleteSelected}
                          >
                            <Trash2 className="h-3 w-3" />
                          </Button>
                        </div>
                      )}
                    </div>
                    <Separator />
                  </>
                )}

                {/* Add term (hidden during selection mode) */}
                {!selectionMode && (
                  <>
                    <div className="flex items-center gap-2 px-4 py-2.5">
                      <Input
                        placeholder="Add term..."
                        className="flex-1 h-8 text-xs rounded-lg"
                        value={newTerm}
                        onChange={(e) => setNewTerm(e.target.value)}
                        onKeyDown={(e) => e.key === "Enter" && handleAddTerm()}
                        disabled={selected.terms.length >= MAX_TERMS}
                      />
                      <Button
                        size="icon-sm"
                        className="h-8 w-8 rounded-lg shrink-0"
                        disabled={!newTerm.trim() || selected.terms.length >= MAX_TERMS}
                        onClick={handleAddTerm}
                      >
                        <Plus className="h-4 w-4" />
                      </Button>
                    </div>
                    <Separator />
                  </>
                )}

                {/* Terms list */}
                <ScrollArea className="flex-1">
                  <div className="flex flex-col">
                    {selected.terms.length === 0 ? (
                      <div className="flex items-center justify-center py-12 text-xs text-muted-foreground">
                        No terms added yet
                      </div>
                    ) : (
                      selected.terms.map((term) => (
                        <div
                          key={term}
                          className={cn(
                            "group flex items-center gap-3 px-4 py-2 transition-colors",
                            selectionMode
                              ? "cursor-pointer hover:bg-muted/40"
                              : "hover:bg-muted/30",
                            selectionMode && selectedTerms.has(term) && "bg-primary/5"
                          )}
                          onClick={selectionMode ? () => toggleTermSelection(term) : undefined}
                        >
                          {selectionMode && (
                            <Checkbox
                              checked={selectedTerms.has(term)}
                              onCheckedChange={() => toggleTermSelection(term)}
                              className="h-3.5 w-3.5"
                            />
                          )}
                          <span className="text-xs text-foreground flex-1">{term}</span>
                          {!selectionMode && (
                            <Button
                              variant="ghost"
                              size="icon-sm"
                              className="h-5 w-5 rounded-md opacity-0 group-hover:opacity-100 transition-opacity hover:text-destructive"
                              onClick={() => handleRemoveTerm(term)}
                            >
                              <X className="h-3 w-3" />
                            </Button>
                          )}
                        </div>
                      ))
                    )}
                  </div>
                </ScrollArea>

                {/* Footer */}
                <Separator />
                <div className="flex items-center justify-end px-4 py-2">
                  <span className="text-[10px] text-muted-foreground">
                    {selected.terms.length} / {MAX_TERMS} terms
                  </span>
                </div>
              </div>
            ) : (
              <div className="flex h-full items-center justify-center text-xs text-muted-foreground">
                Select a vocabulary
              </div>
            )}
          </ResizablePanel>
        </ResizablePanelGroup>

        <Separator />

        {/* Window footer */}
        <div className="flex items-center justify-between px-4 py-3">
          <Label className="text-xs text-muted-foreground">Default vocabulary</Label>
          <div className="flex items-center gap-2">
            <div className="grid grid-cols-2 gap-1">
              {[
                { value: "last" as const, label: "Last used" },
                { value: "specific" as const, label: "Specific" },
              ].map((m) => (
                <button
                  key={m.value}
                  onClick={() => onDefaultModeChange(m.value)}
                  className={cn(
                    "rounded-lg py-1 px-2.5 text-[10px] font-medium transition-all",
                    defaultMode === m.value
                      ? "bg-primary/10 text-primary ring-1 ring-primary/20"
                      : "bg-muted/50 text-muted-foreground hover:bg-muted"
                  )}
                >
                  {m.label}
                </button>
              ))}
            </div>
            {defaultMode === "specific" && (
              <select
                className="h-7 rounded-lg border border-border bg-muted/50 px-2 text-[10px] text-foreground outline-none"
                value={defaultVocabularyId ?? ""}
                onChange={(e) => onDefaultVocabularyIdChange(e.target.value || null)}
              >
                <option value="">Select...</option>
                {vocabularies.map((v) => (
                  <option key={v.id} value={v.id}>{v.name}</option>
                ))}
              </select>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
