creator = {
  name: 'Nils Lundquist'
  email: 'nlundqu@gmail.com'
}

# Utils & Framework
# Encode URI params
getAsUriParameters = (data)->
  return Object.keys(data).map((k)->
    if (Array.isArray(data[k]))
      keyE = encodeURIComponent(k + '[]')
      return data[k].map((subData)->
        keyE + '=' + encodeURIComponent(subData)
      ).join('&')
    else
      return encodeURIComponent(k) + '=' + encodeURIComponent(data[k]);
  ).join('&')

# Copy type instance properties
extend = (target, source) ->
  Object.keys(source).map((prop)->target[prop] = source[prop])
  return target

# Async observable backed by lazily generated promise computed from dependant observables
# Observable value starts as null, lazily generate promise on first use, update value/notify subscribers on promise success. Observable value will update when dependant observables mutate.
asyncComputed = (promise_gen)->
  observable = ko.observable(null)
  current_promise = null

  # wrapped in computed observable to cache result
  async = ko.computed(->
    # abort in-flight evaluation to ensure we only notify with the latest value
    if (current_promise)
      current_promise.reject()

    current_promise = promise_gen().then((value)->
      observable(value)
    ).catch((e)->
      throw(e)
    )
  , @, { deferEvaluation: true })

  return ko.computed(->
    async()
    return observable()
  , @, { deferEvaluation: true})

# Wrap XHR with promise interface
xhr = (options)->
  return new Promise((resolve, reject)->
    req = new XMLHttpRequest()

    req.open(options.method || 'GET', options.url, true)

    if options.content_type
      req.setRequestHeader('Content-Type', options.content_type)

    req.onreadystatechange = (e)->
      if req.readyState != 4
        return

      if [200,304].indexOf(req.status) == -1
        reject(
          new Error('Server responded with a status of ' + req.status)
        )
      else
        resolve(JSON.parse(e.target.response))

    req.send(options.data || '')
  )

# Shuffle groups of potential employees before iterating over them
# to distribute shifts, remove bias from starting position of iteration
Array.prototype.shuffle = ()->
  currentIndex = @length
  while currentIndex != 0
    randomIndex = Math.floor(Math.random() * currentIndex)
    currentIndex--;
    temporaryValue = @[currentIndex]
    @[currentIndex] = @[randomIndex]
    @[randomIndex] = temporaryValue
  return @

# wrap a promise for a data model with a promise for view model
# view model wraps presentation layer on top of data model and presents relevant data from shared data models
# model is promise returning either an object or an array of objects to be wrapped with view_models
view_model = (model, view_model)->
  return new Promise((resolve, reject)->
    wrap = (instance)->
      vm = new view_model()
      vm.model = instance
      return vm

    model.then((value)->
      if (value instanceof Array)
        resolve(value.map((m)->wrap(m)))
      else
        resolve(wrap(m))
    ).catch((e)->
      reject(e);
    )
  )

# ensure every element from one array exists in the other and vice versa
set_equals = (a,b)->
  set_a = new Set(a)
  set_b = new Set(b)
  a_diff = new Set(a.filter((x)-> !set_b.has(x)))
  b_diff = new Set(b.filter((x)-> !set_a.has(x)))
  return a_diff.size == 0 && b_diff.size == 0



# Data Model Types
# Define a generic REST API backed model type
class RESTResource
  host: 'http://interviewtest.replicon.com'
  path: null

  fetch: (options)=>
    return new Promise((resolve, reject)->
      xhr(extend({ url: @host + @path }, options))
        .then((json)=>
          extend(@, json)
          resolve(@)
        )
        .catch((e)-> reject(e))
    )

  save: (options)=>
    return new Promise((resolve, reject)->
      xhr(extend({ url: @host + @path, method: 'POST' }, options))
      .then((json)=>
        extend(@, json)
        resolve(@)
      )
      .catch((e)-> reject(e))    )

  constructor: (instance={})->
    extend(@, instance)

# Define a generic REST API backed collection of model types
class RESTResourceList extends RESTResource
  models: null # list contents
  fetch: ()=>
    return new Promise((resolve, reject)=>
      xhr({ url: @host + @path })
        .then((json)=>
          @models = json.map((raw) => if @type then new @type(raw) else raw)
          resolve(@models)
        )
        .catch((e)-> reject(e))
    )

class EmployeeList extends RESTResourceList
  path: '/employees/'

class TimeoffReqList extends RESTResourceList
  path: '/time-off/requests'

class RuleDefinitionList extends RESTResourceList
  path: '/rule-definitions/'

class ShiftRuleList extends RESTResourceList
  path: '/shift-rules/'


# View Model Types
class Employee
  select: =>
    if (app.active_employee() == @)
      app.active_employee(null)
    else
      app.active_employee(@)

  # test if an employee is off in a given day
  off: (date)=>
    day_index = date.diff(date.clone().startOf('isoweek'), 'days') + 1
    return @timeoff_reqs().some((req)->
      req.week == date.isoWeek() && req.days.some((day)-> day == day_index))

  # test if an employee works in a given day
  works: (date)=>
    return @shifts().some((shift)->date.diff(shift) == 0)

  constructor:()->
    # computed observables for employee specific sets backed by app wide collection
    @shifts = ko.computed(()=>
      if (app.solution())
        app.solution().data
          .map(([_,employees])->employees)
          .reduce(((c, v)->c.concat(v)), [])
          .filter(([employee, _])=>employee==@)
          .reduce(((c, [_, shifts])->c.concat(shifts)), [])
          .map((moment)->moment.toDate())
    )

    @timeoff_reqs = ko.computed(()=>
      if (app.timeoff_reqs())
        app.timeoff_reqs().filter((tor)=>tor.employee_id == @model.id)
      else
        []
    )

# Build a week of dates given a start date
class Week
  constructor:(@start)->
    @days = (@start.clone().add(day, 'days') for day in [0..6])

# create a solution schedule given the employees and rules
class Solution
  @create:(weeks, employees)->
    if (weeks == null or employees == null)
      return null

    if (app.rule_defs() && app.shift_rules())
      per_shift_id = app.rule_defs().find((def)->def.value == 'EMPLOYEES_PER_SHIFT').id
      per_shift = app.shift_rules().find((rule)->rule.rule_id==per_shift_id).value

    return new Solution(weeks, employees, per_shift || 0)

  toJSON:()->
    return @data.map(([week,schedules])->{
      week: week.start.week(),
      schedules: schedules.map(([employee,shifts])->{
          employee_id: employee.model.id,
          schedule: shifts.map((date)->date.diff(week.start, 'days')+1)
      })
    })

  submit: ()=>
    params = {
      name: creator.name,
      email: creator.email
    }

    # NOTE: I couldn't get this to work due to Access-Control-Allow-Headers from server
    # Wouldn't allow required 'Content-Type' header to be set
    xhr({
      url: "#{RESTResource.prototype.host}/submit?#{getAsUriParameters(params)}",
      method: 'POST',
      content_type: 'application/json',
      data: JSON.stringify(@)
    }).then(
      (xhr)-> alert('yay'),
      (e)-> throw e
    )

  solve: ()=>
    # return a set of employees that can work that day
    applyTimeoffRequests = (employees, week, day) ->
      day = day.diff(week.start, 'days') + 1
      week = week.start.isoWeek()
      possible = employees.filter((e)->
        !e.timeoff_reqs().some((tor)-> tor.week == week && tor.days.some((d)->d == day))
      )
      # if no employees available cancel time off and assign randomly
      if possible.length > 0 then possible else employees

    # group possible assignments for like sets of employees, to allow equal distribution
    groupPossibleEmployees = (carry, value)->
      [possible_employees, day] = value

      if (set = carry.find(([pe, _])-> set_equals(pe, possible_employees)))
        null
      else
        set = [possible_employees.shuffle(), []]
        carry.push(set)

      [_, shifts] = set
      shifts.push(day)
      return carry

    # group assignments into shift list from nested [[week,shift]] tuples
    unwrapAssignments = (carry, value)->
      carry.push(value[0][1])
      return carry

    # group shifts for the same individual employee
    groupShifts = (carry, value)->
      v = carry.find(([employee,_])->employee==value[0])
      v[1].push(value[1])
      return carry

    # performs assignment of employee from set of possibilities
    # also take list of assignments and group them into the format expected for a solution
    assign = (assignments)=>
      week = assignments[0][0][0]
      shifts = assignments.reduce(unwrapAssignments, [])
                          .reduce(groupPossibleEmployees, [])

      i = 0
      shifts = ([employee, day] \
        for employee in [possible_employees[(i++) % possible_employees.length]] \
        for day in days \
        for [possible_employees, days] in shifts)
        .map((wrap)->wrap.map((arr)->arr[0])) # undo CoffeeScript list comprehension wrapping
        .reduce(((c,v)->c.concat(v)),[]) # flatten previous grouping
        .reduce(groupShifts, ([employee, []] for employee in @employees)) # group by employee

      return [week, shifts]

    # calculate sets of possible employees for a given day
    # filter out employees with some matching time off request
    # add extra sets of days (i.e shifts) depending on per_shift rule
    possible_assignments = ([week, [possible_employees, day]] \
      for possible_employees in [applyTimeoffRequests(@employees, week, day)] \
      for day in [1..@per_shift].reduce(((c,v)->c.concat(week.days)),[]) \
      for week in @weeks)

    @data = possible_assignments.map(assign)

  constructor: (@weeks, @employees, @per_shift)->
    @solve()



# Root View Model
class App
  rule_defs: asyncComputed((new RuleDefinitionList()).fetch)
  shift_rules: asyncComputed((new ShiftRuleList()).fetch)
  timeoff_reqs: asyncComputed((new TimeoffReqList()).fetch)
  employees: asyncComputed(-> view_model((new EmployeeList()).fetch(), Employee))
  active_employee: ko.observable(null)

  constructor: (from=23, to=26)->
    @from_week = ko.observable(from)
    @to_week = ko.observable(to)
    @weeks = ko.pureComputed(=>
      (new Week(moment().startOf('year').startOf('isoweek').add('weeks', week)) \
      for week in [@from_week()-1..@to_week()-1])
    )
    @solution = ko.computed(=>
      Solution.create(@weeks(), @employees())
    )



# Initialize app
document.addEventListener("DOMContentLoaded", ->
  #Initialize View
  window.app = new App()
  ko.applyBindings(app)
)