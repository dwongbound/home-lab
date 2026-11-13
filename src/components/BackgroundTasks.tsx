import type { RunningTask } from '../types'

// Beside the orb on /talk (Dylan, 2026-11-12): the work he's sent off to
// run in the background, like a change to Jarvis's code, each with a
// spinner while it runs. A job leaves the list when it finishes. Nothing
// shows when nothing is running.

/** The running and queued background jobs, or nothing when there are none. */
export function BackgroundTasks({ tasks }: { tasks: RunningTask[] }) {
  if (tasks.length === 0) return null
  return (
    <ul className="bgtasks" aria-label="Working on in the background">
      {tasks.map((task) => (
        <li key={task.id} className="bgtasks__item" data-state={task.state}>
          <span className="bgtasks__ring" aria-hidden="true" />
          <span className="bgtasks__label">{task.label}</span>
          {task.state === 'queued' ? <span className="bgtasks__queued">Up next</span> : null}
        </li>
      ))}
    </ul>
  )
}
