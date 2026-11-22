require 'ferrum'

browser = Ferrum::Browser.new(headless: true)

browser.go_to("https://playlist.brgen.no")
browser.execute("document.querySelector('iframe').contentWindow.postMessage('play', '*')")
sleep 2
browser.screenshot(path: "RAILS/playlist_dilla.webp", full: true)

browser.go_to("https://brgen.no/master/plur1bus")
sleep 2
browser.screenshot(path: "MASTER/plur1bus_face.webp", full: true)

browser.quit
