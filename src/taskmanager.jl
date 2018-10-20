struct TaskManager
    queue::Channel{Task}
    task::Base.RefValue{Task}
end

TaskManager() = TaskManager(Channel{Task}(Inf), Ref{Task}())

function launch!(m::TaskManager)
    m.task[] = @async for (i, t) in enumerate(m.queue)
        try
            schedule(t)
            wait(t)
        catch exception
            @error "Error from $i-th task" exception
        end
    end
end

get_ready!(m::TaskManager) = isassigned(m.task) || launch!(m)

function enqueue!(m::TaskManager, t::Task)
    get_ready!(m)
    push!(m.queue, t)
    return
end


const taskmanager = Ref{TaskManager}()

function _taskmanager()
    if !isassigned(taskmanager)
        taskmanager[] = TaskManager()
    end
    return taskmanager[]
end

enqueue(t::Task) = enqueue!(_taskmanager(), t)
