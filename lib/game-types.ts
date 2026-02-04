import type { ComponentType } from 'react'

export type GameId = 'spyfall' | 'secret-hitler' | 'codenames' | 'betrayal'

export interface GameDef {
  id: GameId
  name: string
  maxPlayers: number
  minPlayers: number
  rules: string
  component: ComponentType
}

export const GAME_REGISTRY: Record<GameId, GameDef> = {} as Record<GameId, GameDef>

export function registerGame(def: GameDef) {
  GAME_REGISTRY[def.id] = def
}

export function getGame(id: GameId): GameDef | undefined {
  return GAME_REGISTRY[id]
}

export function getAllGames(): GameDef[] {
  return Object.values(GAME_REGISTRY)
}
