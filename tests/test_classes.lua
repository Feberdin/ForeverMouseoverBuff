-- Purpose: exercise class-specific direct buffs and conservative boundaries.
-- Input: invented public snapshots. Output: assertions and PASS; no game/network.
-- Invariant: preserve Paladin replacement rules and reject unsafe utility defaults.
-- Debug: lua5.1 tests/test_classes.lua from the repository root.
local ns = {}
assert(loadfile('src/ForeverMouseoverBuff/Core.lua'))('ForeverMouseoverBuff', ns)
local function context(class, family)
    return { playerClass=class, playerCombat=false, mounted=false, flying=false, inVehicle=false,
        mode='auto', auraState='ready', hasBlessing=false, blessings={},
        target={exists=true,isPlayer=true,friendly=true,pvp=false,freeForAll=false,dead=false,isSelf=false,connected=true,
            visible=true,class='MAGE',level=60},
        spells={{spellID=100,spellName='Synthetic Buff',family=family,learnedLevel=1,
            known=true,inRange=true,usable=true}} }
end
local function expect(value, expected, label)
    assert(value == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(value))
end
-- This must fail on the Paladin-only baseline for an actual policy reason.
for _, row in ipairs({{'MAGE','intellect'},{'PRIEST','fortitude'},{'DRUID','mark'},
    {'WARLOCK','breath'},{'SHAMAN','water_breathing'}}) do
    local c=context(row[1],row[2])
    expect(ns.Core.Decide(c).ready,true,row[1] .. ' can buff')
    c.spells[2]={spellID=101,spellName='Synthetic higher rank',family=row[2],learnedLevel=70,
        known=true,inRange=true,usable=true}
    expect(ns.Core.Decide(c).spellID,100,'recipient rank limit')
    c.spells[1].usable=false
    expect(ns.Core.Decide(c).code,'NOT_USABLE','mana/reagent gate')
    c.spells[1].usable=true; c.spells[1].inRange=false
    expect(ns.Core.Decide(c).code,'OUT_OF_RANGE','range gate')
    c.spells[1].inRange=true
    c.hasBlessing=true; c.blessings={{spellID=100,family=row[2],sourceIsPlayer=false}}
    expect(ns.Core.Decide(c).ready,false,'existing equivalent buff preserved')
end
local c=context('MAGE','intellect'); c.target.class='WARRIOR'
expect(ns.Core.Decide(c).code,'CLASS_DISABLED','mana-only buff skipped for warrior')
c=context('DRUID','thorns'); c.hasBlessing=true
c.blessings={{spellID=1126,family='mark',sourceIsPlayer=true}}
expect(ns.Core.Decide(c).ready,true,'own mark allows additional thorns')
c=context('MAGE','dampen'); expect(ns.Core.Decide(c).ready,false,'utility never auto-selected')
c.mode='dampen'; expect(ns.Core.Decide(c).ready,true,'utility explicit choice')
c.mode='might'; expect(ns.Core.Decide(c).code,'INVALID_MODE','foreign family refused')
for _,class in ipairs({'WARRIOR','ROGUE','HUNTER'}) do
    expect(ns.Core.Decide(context(class,'might')).code,'UNSUPPORTED_CLASS',class .. ' explained')
end
for _,mutation in ipairs({'dead','isSelf'}) do
    c=context('PRIEST','fortitude'); c.target[mutation]=true
    expect(ns.Core.Decide(c).ready,false,'unsafe recipient rejected')
end
c=context('SHAMAN','water_walking'); expect(ns.Core.Decide(c).ready,false,'walking never automatic')
c.mode='water_walking'; expect(ns.Core.Decide(c).ready,true,'walking explicit')

-- The existing anonymous attempt observer must retain new family/mode tokens.
issecretvalue=function() return false end
canaccesstable=function() return true end
assert(loadfile('src/ForeverMouseoverBuff/AttemptTrace.lua'))('ForeverMouseoverBuff', ns)
local facts=context('MAGE','intellect'); facts.mode='intellect'
local captured=ns.AttemptTrace.Capture(facts,
    {spellID=1459,family='intellect',code='READY'})
expect(captured.family,'intellect','new family diagnostic token')
expect(captured.mode,'intellect','new mode diagnostic token')
print('PASS: six direct-buff classes, three explained classes, rank/mana/range/aura/utility safety and diagnostic tokens')
