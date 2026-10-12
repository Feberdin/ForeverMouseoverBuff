/* Purpose: fetch and display aggregate ranking rows from the same-origin service.
 * Input: two select values. Output: text-only table cells and clear status messages.
 * Invariant: player names never become HTML. Debug: visible status, no identity logs. */
"use strict";
const group = document.getElementById("group");
const buff = document.getElementById("buff");
const refresh = document.getElementById("refresh");
const status = document.getElementById("status");
let requestNumber = 0;

// Each request owns a serial: a slower previous response must not replace a newer filter.
async function loadRanking() {
  const currentRequest = ++requestNumber;
  refresh.disabled = true;
  status.textContent = "Rangliste wird geladen …";
  const params = new URLSearchParams({group: group.value, limit: "100"});
  if (buff.value) params.set("buff", buff.value);
  try {
    const response = await fetch("/v1/leaderboard?" + params, {cache: "no-store"});
    if (!response.ok) throw new Error("HTTP " + response.status);
    const data = await response.json();
    if (currentRequest !== requestNumber) return;
    if (!Array.isArray(data.rows) || data.trust !== "self_reported") throw new Error("API-Vertrag");
    const rows = document.getElementById("rows");
    rows.replaceChildren();
    for (const entry of data.rows) {
      const row = document.createElement("tr");
      const name = data.group === "players" ? entry.displayName + " · " + entry.realm :
        data.group === "classes" ? (entry.casterClass === "PALADIN" ? "Paladin" : entry.casterClass) : entry.label;
      for (const text of [entry.rank, name, entry.count]) {
        const cell = document.createElement("td");
        cell.textContent = String(text);
        row.appendChild(cell);
      }
      rows.appendChild(row);
    }
    document.getElementById("caption").textContent = group.options[group.selectedIndex].text;
    status.textContent = data.rows.length ? `${data.total} angenommene Community-Meldungen · Stand ${new Date(data.generatedAt * 1000).toLocaleString("de-DE")}` : "Noch keine Meldungen für diese Auswahl vorhanden.";
  } catch (error) {
    if (currentRequest === requestNumber) {
      document.getElementById("rows").replaceChildren();
      status.textContent = "Rangliste nicht erreichbar. Lokalen Dienst prüfen und erneut auf Aktualisieren klicken.";
    }
  } finally {
    if (currentRequest === requestNumber) refresh.disabled = false;
  }
}
group.addEventListener("change", loadRanking);
buff.addEventListener("change", loadRanking);
refresh.addEventListener("click", loadRanking);
loadRanking();
