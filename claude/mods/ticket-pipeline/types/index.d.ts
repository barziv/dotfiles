export type StageStatus = 'pending' | 'active' | 'done' | 'failed'
export type Pipeline = { ticket: string; stages: Record<string, StageStatus> }

export type Check = { name: string; url: string }
export type Pr = {
  number: number
  url: string
  state: string
  isDraft: boolean
  review: string
  passed: number
  pending: number
  failed: Check[]
}

declare module 'claude-code' {
  interface PluginState {
    'ticket-pipeline': {
      pipeline: Pipeline | null
      pr: Pr | null
    }
  }
}
