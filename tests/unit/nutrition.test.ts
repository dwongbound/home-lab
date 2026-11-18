import { describe, expect, it } from 'vitest'
import { parseNutrition } from '../../server/sources/nutrition.mjs'

describe('parseNutrition', () => {
  it('keeps the numbers, renames protein_goal and lets left go negative', () => {
    expect(parseNutrition({ date: '2026-11-18', eaten: 1900, goal: 1750, left: 0, burned: 410, protein: 120, protein_goal: 140 })).toEqual({
      date: '2026-11-18', eaten: 1900, goal: 1750, left: -150, burned: 410, protein: 120, proteinGoal: 140,
    })
  })

  it('is null without a date, eaten or goal, and drops odd extras', () => {
    expect(parseNutrition(null)).toBeNull()
    expect(parseNutrition({ date: 'today', eaten: 1, goal: 2 })).toBeNull()
    expect(parseNutrition({ date: '2026-11-18', eaten: '1200', goal: 1750 })).toBeNull()
    expect(parseNutrition({ date: '2026-11-18', eaten: 1200, goal: 0 })).toBeNull()
    expect(parseNutrition({ date: '2026-11-18', eaten: 0, goal: 1750, burned: 'lots', meals: ['ramen'] })).toEqual({
      date: '2026-11-18', eaten: 0, goal: 1750, left: 1750, burned: null, protein: null, proteinGoal: null,
    })
  })
})
