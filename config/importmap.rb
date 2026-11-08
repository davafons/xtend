# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "d3-force" # @3.0.1
pin "d3-dispatch" # @3.0.2
pin "d3-quadtree" # @3.0.2
pin "d3-timer" # @3.0.2
# Chart.js comes from jsDelivr's single-file ESM build (https://cdn.jsdelivr.net/npm/chart.js@4.6.1/+esm), because the
# jspm download imports a shared chunk it does not vendor. Its one import is rewritten to "@kurkle/color".
pin "chart.js" # @4.6.1
pin "@kurkle/color", to: "@kurkle--color.js" # @0.3.4
