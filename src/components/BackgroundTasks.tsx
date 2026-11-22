import { chipFor } from '../lib/model'
import type { RunningTask } from '../types'

// Beside the orb on /talk (Dylan, 2026-11-12): the work he's sent off to
// run in the background, like a change to Jarvis's code, each with a
// spinner while it runs. A job leaves the list when it finishes. Nothing
// shows when nothing is running. Each says who's doing it, with the same
// chip as a chat reply: "Jarvis (CO)" for Opus, "(CF)" Fable, "(O)" Ornith
// (Dylan, 2026-11-19); no chip when plain code is. Under the label, one line
// on where it's at ("Running tests"), when Jarvis says.

/** The chip naming the model on one job, or nothing when no model is doing it. */
function TaskModel({ model }: { model: string | null }) {
  if (model === null) return null
  const chip = chipFor(model)
  return <span className="chat__model bgtasks__model" data-model={chip.tone}>{chip.label}</span>
}

/** The running and queued background jobs, or nothing when there are none. */
export function BackgroundTasks({ tasks }: { tasks: RunningTask[] }) {
  if (tasks.length === 0) return null
  return (
    <ul className="bgtasks" aria-label="Working on in the background">
      {tasks.map((task) => (
        <li key={task.id} className="bgtasks__item" data-state={task.state}>
          <span className="bgtasks__ring" aria-hidden="true" />
          <span className="bgtasks__label">{task.label}</span>
          <TaskModel model={task.model} />
          {task.step ? <span className="bgtasks__step">{task.step}</span> : null}
          {task.state === 'queued' ? <span className="bgtasks__queued">Up next</span> : null}
        </li>
      ))}
    </ul>
  )
}
