import { describe, expect, it } from 'vitest'
import { dayCount, isDay, isMealId, photoType, parseNutrition, parseNutritionDay, parseNutritionDays, parseNutritionWeek } from '../../server/sources/nutrition.mjs'

describe('parseNutrition', () => {
  it('keeps the numbers, renames protein_goal and lets left go negative', () => {
    expect(parseNutrition({ date: '2026-11-18', eaten: 1900, goal: 1750, left: 0, burned: 410, protein: 120, protein_goal: 140 })).toEqual({
      date: '2026-11-18', eaten: 1900, goal: 1750, left: -150, burned: 410, protein: 120, proteinGoal: 140, fat: null, fatGoal: null, carbs: null, carbsGoal: null,
    })
  })

  it('is null without a date, eaten or goal, and drops odd extras', () => {
    expect(parseNutrition(null)).toBeNull()
    expect(parseNutrition({ date: 'today', eaten: 1, goal: 2 })).toBeNull()
    expect(parseNutrition({ date: '2026-11-18', eaten: '1200', goal: 1750 })).toBeNull()
    expect(parseNutrition({ date: '2026-11-18', eaten: 1200, goal: 0 })).toBeNull()
    expect(parseNutrition({ date: '2026-11-18', eaten: 0, goal: 1750, burned: 'lots', meals: ['ramen'] })).toEqual({
      date: '2026-11-18', eaten: 0, goal: 1750, left: 1750, burned: null, protein: null, proteinGoal: null, fat: null, fatGoal: null, carbs: null, carbsGoal: null,
    })
  })
})

describe('parseNutritionDay', () => {
  const item = { id: 7, at: '2026-11-18T20:15:00-08:00', name: ' Chicken bowl ', portion: '1 bowl', calories: 640, protein: 48.26, fat: 18, carbs: 62, has_photo: true }

  it('gives the day in the page\'s shape with items in time order', () => {
    const day = parseNutritionDay({
      date: '2026-11-18',
      goals: { calories: 1750, protein: 140, fat: 60, carbs: 160 },
      totals: { calories: 890, protein: 60.3, fat: 25, carbs: 90, burned: 410 },
      items: [item, { id: 'b', at: '2026-11-18T08:00:00-08:00', name: 'Latte', calories: 250 }],
    })
    expect(day?.items.map((one: { name: string }) => one.name)).toEqual(['Latte', 'Chicken bowl'])
    expect(day?.items[1]).toEqual({ id: '7', at: item.at, name: 'Chicken bowl', portion: '1 bowl', calories: 640, protein: 48.3, fat: 18, carbs: 62, hasPhoto: true })
    expect(day?.items[0]).toMatchObject({ portion: null, protein: null, hasPhoto: false })
    expect(day?.goals).toEqual({ calories: 1750, protein: 140, fat: 60, carbs: 160 })
    expect(day?.totals).toEqual({ calories: 890, protein: 60.3, fat: 25, carbs: 90, burned: 410 })
  })

  it('drops broken items and keeps a day with no goals', () => {
    const day = parseNutritionDay({ date: '2026-11-18', items: [{ id: 1, name: 'No time' }, { id: 2, at: 'soon', name: 'Bad time' }, { at: item.at, name: 'No id' }, { id: 3, at: item.at, name: '  ' }, null] })
    expect(day).toEqual({ date: '2026-11-18', goals: { calories: null, protein: null, fat: null, carbs: null }, totals: { calories: null, protein: null, fat: null, carbs: null, burned: null }, items: [] })
  })

  it('is null for anything that isn\'t a day', () => {
    expect(parseNutritionDay(null)).toBeNull()
    expect(parseNutritionDay({ date: 'today', items: [] })).toBeNull()
    expect(parseNutritionDay({ date: '2026-11-18' })).toBeNull()
  })
})

describe('parseNutritionWeek', () => {
  it('keeps at most seven dated days', () => {
    const days = Array.from({ length: 9 }, (_, index) => ({ date: `2026-11-1${index}`, calories: 1500 + index, goal: 1750, protein: 100.04, protein_goal: 140 }))
    const week = parseNutritionWeek({ start: '2026-11-10', days: [{ date: 'nope' }, ...days] })
    expect(week?.start).toBe('2026-11-10')
    expect(week?.days).toHaveLength(7)
    expect(week?.days[0]).toEqual({ date: '2026-11-10', calories: 1500, goal: 1750, protein: 100, proteinGoal: 140, fat: null, fatGoal: null, carbs: null, carbsGoal: null })
  })

  it('gives null numbers for a day with nothing logged, and null for a non-week', () => {
    expect(parseNutritionWeek({ start: '2026-11-10', days: [{ date: '2026-11-10' }] })?.days).toEqual([{ date: '2026-11-10', calories: null, goal: null, protein: null, proteinGoal: null, fat: null, fatGoal: null, carbs: null, carbsGoal: null }])
    expect(parseNutritionWeek({ start: '2026-11-10' })).toBeNull()
    expect(parseNutritionWeek({ start: 'monday', days: [] })).toBeNull()
  })
})

describe('isDay', () => {
  it('takes only YYYY-MM-DD', () => {
    expect(isDay('2026-11-18')).toBe(true)
    expect(isDay('11/18/2026')).toBe(false)
    expect(isDay(20261118)).toBe(false)
  })
})

describe('parseNutritionDays', () => {
  it('gives the days newest first with where the log begins, and drops what is not a day', () => {
    const day = (date: string) => ({ date, goals: {}, totals: {}, items: [] })
    const run = parseNutritionDays({ days: [day('2026-11-16'), { date: 'nope' }, day('2026-11-17')], earliest: '2026-10-02' })
    expect(run?.days.map((d: { date: string }) => d.date)).toEqual(['2026-11-17', '2026-11-16'])
    expect(run?.earliest).toBe('2026-10-02')
    expect(parseNutritionDays({ days: [], earliest: 'long ago' })).toEqual({ days: [], earliest: null })
    expect(parseNutritionDays({ earliest: '2026-10-02' })).toBeNull()
  })

  it('reads how many days were asked for', () => {
    expect(dayCount(null)).toBe(7)
    expect(dayCount('3')).toBe(3)
    expect(dayCount('0')).toBe(1)
    expect(dayCount('99')).toBe(14)
    expect(dayCount('-2')).toBeNull()
    expect(dayCount('many')).toBeNull()
  })
})

describe('meal photos', () => {
  it('knows a meal id and the picture kinds the apps can show', () => {
    expect(isMealId('42')).toBe(true)
    expect(isMealId('../x')).toBe(false)
    expect(isMealId('')).toBe(false)
    expect(photoType('image/png')).toBe('image/png')
    expect(photoType('IMAGE/JPEG; q=1')).toBe('image/jpeg')
    expect(photoType('text/html')).toBe('image/jpeg')
    expect(photoType(null)).toBe('image/jpeg')
  })

  it('carries fat and carbs against their goals, today and across a week', () => {
    const today = parseNutrition({ date: '2026-11-19', eaten: 900, goal: 1750, fat: 30.4, fat_goal: 55, carbs: 88, carbs_goal: 175 })
    expect(today).toMatchObject({ fat: 30.4, fatGoal: 55, carbs: 88, carbsGoal: 175 })
    const week = parseNutritionWeek({ start: '2026-11-16', days: [{ date: '2026-11-16', fat: 41, fat_goal: 55, carbs: 150, carbs_goal: 175 }] })
    expect(week?.days[0]).toMatchObject({ fat: 41, fatGoal: 55, carbs: 150, carbsGoal: 175 })
  })
})
