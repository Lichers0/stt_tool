"use client"

import { Mic, Accessibility, KeyRound, CheckCircle2, Circle, ArrowRight } from "lucide-react"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

interface Permission {
  id: string
  label: string
  description: string
  icon: React.ReactNode
  granted: boolean
  actionLabel: string
}

interface PermissionsScreenProps {
  permissions: Permission[]
  onGrantPermission: (id: string) => void
  onContinue: () => void
}

export function PermissionsScreen({ permissions, onGrantPermission, onContinue }: PermissionsScreenProps) {
  const allRequired = permissions
    .filter((p) => p.id !== "keychain")
    .every((p) => p.granted)

  return (
    <div className="flex flex-col items-center gap-5 p-5">
      <div className="flex flex-col items-center gap-2 text-center">
        <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10">
          <Mic className="h-6 w-6 text-primary" />
        </div>
        <h2 className="text-base font-semibold text-foreground">STT Tool Setup</h2>
        <p className="text-xs text-muted-foreground leading-relaxed">
          Grant permissions to enable voice transcription.
        </p>
      </div>

      <div className="flex w-full flex-col gap-3">
        {permissions.map((perm, index) => (
          <div
            key={perm.id}
            className={cn(
              "flex items-start gap-3 rounded-xl p-3 transition-colors",
              perm.granted
                ? "bg-primary/5"
                : "bg-muted/50"
            )}
          >
            <div className="flex h-6 w-6 shrink-0 items-center justify-center">
              {perm.granted ? (
                <CheckCircle2 className="h-5 w-5 text-green-500" />
              ) : (
                <div className="flex h-5 w-5 items-center justify-center rounded-full border-2 border-muted-foreground/30">
                  <span className="text-[10px] font-medium text-muted-foreground">{index + 1}</span>
                </div>
              )}
            </div>
            <div className="flex flex-1 flex-col gap-1.5">
              <div className="flex items-center gap-2">
                {perm.icon}
                <span className="text-sm font-medium text-foreground">{perm.label}</span>
              </div>
              <p className="text-xs text-muted-foreground leading-relaxed">{perm.description}</p>
              {!perm.granted && (
                <Button
                  variant="outline"
                  size="sm"
                  className="mt-1 w-fit text-xs h-7 px-3 rounded-lg"
                  onClick={() => onGrantPermission(perm.id)}
                >
                  {perm.actionLabel}
                </Button>
              )}
            </div>
          </div>
        ))}
      </div>

      <Button
        className="w-full rounded-xl h-9"
        disabled={!allRequired}
        onClick={onContinue}
      >
        Continue
        <ArrowRight className="h-4 w-4" />
      </Button>
    </div>
  )
}

export const defaultPermissions: Permission[] = [
  {
    id: "microphone",
    label: "Microphone",
    description: "Required to record speech.",
    icon: <Mic className="h-3.5 w-3.5 text-muted-foreground" />,
    granted: false,
    actionLabel: "Grant Access",
  },
  {
    id: "accessibility",
    label: "Accessibility",
    description: "Required to paste text into other apps.",
    icon: <Accessibility className="h-3.5 w-3.5 text-muted-foreground" />,
    granted: false,
    actionLabel: "Open Settings",
  },
  {
    id: "keychain",
    label: "Keychain",
    description: "Secure storage for API keys.",
    icon: <KeyRound className="h-3.5 w-3.5 text-muted-foreground" />,
    granted: false,
    actionLabel: "Retry",
  },
]
