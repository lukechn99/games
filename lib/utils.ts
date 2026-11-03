import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/** "2 players" or "3–6 players". */
export function playerRange(min: number, max: number): string {
  return min === max ? `${min} players` : `${min}–${max} players`
}
