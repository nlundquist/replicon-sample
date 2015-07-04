# Replicon Test Assignment

   Implements a simple automated scheduling system.

   Loads employee list and rules at load time and calculates a solution.

   Displays an interface displaying the days an employee works in the calculated solution.

   Run by opening index.html. Comes with SCSS & Coffeescript already compiled.

   * Uses CoffeeScript for list comprehensions, destructuring assignment & lightweight function syntax.
   * Uses ES6 for Array prototype extensions, Promise, etc. via ES6-shim library.
   * Uses Moment.js for date manipulations and comparisons.
   * Uses Knockout.js for view layer & observable implementations used in view models.


   Included in this solution are a simple reuseable model layer implementation (using promise wrapped native XHR),
   an extension to Knockout observables to support a promise interface, and promise based view model 'factory'
   helper.

   I tried to keep everything in a single file for ease of analysis and since I didn't have any paritcular
   style guidelines considering Knockout was the only framework I used, and its rather non-perscriptive. I
   also wanted to avoid the topic of code resource packaging & loading in Javascript, which while very
   important is probably overkill for a sample such as this. Thus chose to err on the side of simplicity.

   If I was doing this at a broader scale I'd have a very different file hierarchy and use a module loader
   such as RequireJS or StealJS.

   Typically I wouldn't commit generated JS and CSS to the code repo, however as this is being hosted on
   GitHub pages, in the interest of simplicty I've foregone a more involved deployment process.

   * Assumptions:
      * Need to staff 7 days a week
      * Statuory holidays are a future requirement rather than an unspoken one
      * Desire to fairly (at least somewhat) distribute shifts
      * If all employees have booked a day off, ignore all time off requests for that day