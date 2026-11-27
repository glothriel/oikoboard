// Drive the Flutter web build in headless Chrome and take screenshots. Called by screens.sh:
//   node shot.mjs <cdp url> <app url> <steps.json> <out dir>
// steps.json: [{ "name": "task-editor", "width": 390, "height": 800,
//                "actions": [{ "click": [195, 400] }, { "wait": 1500 }, { "type": "Milk" },
//                            { "key": "Enter" }, { "shot": "after-typing" }] }]
// Every screen starts from a fresh load of the app; the final state is saved as <name>.png,
// `{ "shot": "x" }` saves an intermediate <name>.x.png (useful to find click coordinates).
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import { readFileSync, mkdirSync } from 'node:fs';

const require = createRequire(execSync('npm root -g').toString().trim() + '/');
const { chromium } = require('playwright-core');
const [cdp, appUrl, stepsFile, outDir] = process.argv.slice(2);
const screens = JSON.parse(readFileSync(stepsFile, 'utf8'));
mkdirSync(outDir, { recursive: true });

const browser = await chromium.connectOverCDP(cdp);
const context = browser.contexts()[0];
try {
  for (const screen of screens) {
    const page = await context.newPage();
    // Device scale 1: a CDP scale override makes Flutter lay out wrong and crops the shot.
    await page.setViewportSize({ width: screen.width ?? 390, height: screen.height ?? 800 });
    await page.goto(appUrl);
    await page.waitForTimeout(screen.loadWait ?? 4000); // canvas app: no DOM to wait for
    for (const a of screen.actions ?? []) {
      if (a.click) await page.mouse.click(a.click[0], a.click[1]);
      else if (a.wait) await page.waitForTimeout(a.wait);
      else if (a.type !== undefined) await page.keyboard.type(a.type);
      else if (a.key) await page.keyboard.press(a.key);
      else if (a.scroll) await page.mouse.wheel(0, a.scroll);
      else if (a.shot) await page.screenshot({ path: `${outDir}/${screen.name}.${a.shot}.png` });
      else throw new Error(`unknown action ${JSON.stringify(a)}`);
      if (a.click || a.key) await page.waitForTimeout(a.after ?? 1200);
    }
    await page.screenshot({ path: `${outDir}/${screen.name}.png` });
    console.log(`${outDir}/${screen.name}.png`);
    await page.close();
  }
} finally {
  await browser.close();
}
