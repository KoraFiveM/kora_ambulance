# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_ambulance — Police & EMS

  @kora_ambulance @checklist @checklist:kora_ambulance:ems-duty @cat:police-and-ems
  Scenario: EMS duty toggle (/ems-duty)
    """
    Checklist test: As ambulance job run /ems-duty (or hospital duty target); duty state flips and gates other EMS options.
    """
    Given my job is "ambulance"
    And I am off duty
    When I run the command "/ems-duty"
    Then I should be on duty
    And I should see a notification containing "You are now on duty."
    When I run the command "/ems-duty"
    Then I should be off duty
    And I should see a notification containing "You are now off duty."
    And I confirm: EMS-only options (e.g. hospital duty target, duty vehicle) are available only while I am on duty

  @kora_ambulance @checklist @checklist:kora_ambulance:laststand-bleedout @cat:police-and-ems
  Scenario: Downed state and bleed-out timer
    """
    Checklist test: Get downed: laststand screen with bleed-out clock; controls locked but camera look allowed; die when timer ends.
    """
    Given I am revived
    When I manually: get downed (e.g. take damage until I drop into laststand)
    Then I confirm: the laststand screen shows a bleed-out clock
    And I confirm: my movement controls are locked
    And I confirm: I can still look around with the camera
    When I manually: wait for the bleed-out timer to end without any help
    Then I should be dead

  @kora_ambulance @checklist @checklist:kora_ambulance:respawn-command @cat:police-and-ems
  Scenario: Respawn at hospital (/respawn)
    """
    Checklist test: After dying wait respawnTime (60s) then /respawn: wake at hospital bed and get billed; blocked early with server message.
    """
    Given I am dead
    When I run the command "/respawn"
    Then I should see a notification containing "You cannot respawn for another"
    When I wait 60 seconds
    And I run the command "/respawn"
    Then I confirm: I wake up on a hospital bed
    And I should be alive
    And I should see a notification containing "You were billed"
    And I confirm: money was taken from my cash or bank

  @kora_ambulance @checklist @checklist:kora_ambulance:alert-ems-key @cat:police-and-ems
  Scenario: Alert EMS key (G) while dead
    """
    Checklist test: While dead press G: dispatch call goes to on-duty EMS; reply says if anyone is on duty; 60s cooldown.
    """
    Given I am dead
    When I press the "G" key
    Then I confirm: a dispatch call is sent to on-duty EMS
    And I confirm: I get a reply saying whether any paramedics are on duty
    When I press the "G" key
    Then I should see a notification containing "You already alerted EMS. Try again in"

  @kora_ambulance @checklist @checklist:kora_ambulance:emergency-call-911e @cat:police-and-ems @manual
  Scenario: /911e emergency call
    """
    Checklist test: Run /911e <message>: priority-1 call appears for on-duty EMS in dispatch; caller told if no medics.
    """
    When I manually: run /911e with a short message while no medics are on duty
    Then I confirm: I am told "No paramedics are currently on duty." (only applies when no medics are on duty)
    When I manually: ask a second player with the ambulance job on duty to watch dispatch
    And I manually: run /911e with a short message
    Then I confirm: the other player sees a priority-1 call with my message in dispatch

  @kora_ambulance @checklist @checklist:kora_ambulance:auto-casualty-call @cat:police-and-ems @manual
  Scenario: Automatic person-down calls
    """
    Checklist test: Go down: an automatic dispatch call is raised once per cooldown and closes when revived.
    """
    When I manually: ask a second player with the ambulance job on duty to watch dispatch
    And I manually: get downed (take damage until in laststand)
    Then I confirm: the other player sees an automatic person-down dispatch call
    When I manually: go down again within the cooldown
    Then I confirm: the other player sees no second call during the cooldown
    When I manually: ask the second player to revive me
    Then I confirm: the other player sees the dispatch call closed

  @kora_ambulance @checklist @checklist:kora_ambulance:wounds-tracking @cat:police-and-ems
  Scenario: Persistent per-body-part wounds
    """
    Checklist test: Get shot/hurt: wound recorded per bone, tier 1-4 movement penalty (limp), persists across reconnect.
    """
    Given I am revived
    When I manually: get shot or hurt (e.g. take damage to a leg)
    Then I confirm: a wound is recorded for the injured body part
    And I confirm: I limp with a movement penalty that matches the wound tier (1-4)
    When I manually: disconnect and reconnect to the server
    Then I confirm: my wounds and limp are still present

  @kora_ambulance @checklist @checklist:kora_ambulance:assess-patient @cat:police-and-ems
  Scenario: Assess Patient (target)
    """
    Checklist test: On-duty medic ALT-target an injured player: Assess Patient shows head-to-toe wound summary.
    """
    Given my job is "ambulance"
    And I am on duty
    When I manually: ask a second player to get injured and stand next to me
    And I manually: ALT-target the injured player and choose Assess Patient
    Then I confirm: Assess Patient shows a head-to-toe wound summary

  @kora_ambulance @checklist @checklist:kora_ambulance:treat-wound @cat:police-and-ems
  Scenario: Treat Wound
    """
    Checklist test: Medic target Treat Wound: 5s cancellable action, bandage for tier 1-2, IFAK for tier 3-4; item consumed.
    """
    Given my job is "ambulance"
    And I am on duty
    And I have 1 "bandage"
    And I have 1 "ifak"
    When I manually: ask a second player with a tier 1-2 wound to stand next to me
    And I manually: target the patient and choose Treat Wound
    Then a progress bar should run
    And I confirm: the 5 second progress action can be cancelled
    And my "bandage" count should have changed by -1
    When I manually: repeat Treat Wound on a patient with a tier 3-4 wound
    Then my "ifak" count should have changed by -1

  @kora_ambulance @checklist @checklist:kora_ambulance:cpr-revive @cat:police-and-ems
  Scenario: Perform CPR on downed player
    """
    Checklist test: Medic target downed player > Perform CPR, or use the defibrillator item; patient revived; revive hooks fire.
    """
    Given my job is "ambulance"
    And I am on duty
    And I have 1 "defibrillator"
    When I manually: ask a second player to get downed and stand next to me
    And I manually: target the downed player and choose Perform CPR
    Then I confirm: the other player is revived
    When I manually: ask the second player to get downed again
    And I use the "defibrillator"
    Then I confirm: the other player is revived
    And there should be no script errors

  @kora_ambulance @checklist @checklist:kora_ambulance:emergency-carry @cat:police-and-ems
  Scenario: Emergency Carry
    """
    Checklist test: Target a downed player and choose Emergency Carry to carry them; release works.
    """
    When I manually: ask a second player to get downed and stand next to me
    And I manually: target the downed player and choose Emergency Carry
    Then I should see a notification containing "Emergency carry started."
    And I confirm: I am carrying the downed player
    When I manually: release the carried player
    Then I confirm: the player is released and put down

  @kora_ambulance @checklist @checklist:kora_ambulance:stretcher @cat:police-and-ems
  Scenario: Ambulance stretcher
    """
    Checklist test: Target ambulance: Deploy Stretcher; Load onto Stretcher, Push Stretcher, Stow/Unstow Stretcher with patient.
    """
    Given my job is "ambulance"
    And I am on duty
    When I manually: go to an ambulance at the hospital and target it
    And I manually: select Deploy Stretcher
    Then I confirm: a stretcher is deployed next to the ambulance
    When I manually: ask a second player to lie down as a patient near the stretcher
    And I manually: target the stretcher and select Load onto Stretcher
    Then I confirm: the patient is loaded onto the stretcher
    When I manually: select Push Stretcher and push it
    Then I confirm: the stretcher with the patient moves while pushed
    When I manually: select Stow Stretcher with the patient on it, then Unstow it
    Then I confirm: the stretcher with the patient stows and unstows correctly

  @kora_ambulance @checklist @checklist:kora_ambulance:hospital-checkin @cat:police-and-ems
  Scenario: Hospital check-in and bed care
    """
    Checklist test: Injured player uses Check In for Care at a desk: bed reserved, 15s care, healed, $250 fee; E leaves early.
    """
    Given my health is 40%
    And my cash balance is 500
    When I manually: go to a hospital check-in desk
    And I manually: select Check In for Care
    Then I should see a notification containing "Assigned to bed"
    And I confirm: I am placed on my assigned bed
    When I wait 15 seconds
    Then I should see a notification containing "Care completed."
    And I confirm: my health is restored
    And my cash balance should have changed by -250
    When I manually: check in again and press E to leave the bed early
    Then I should see a notification containing "Your bed reservation was released."

  @kora_ambulance @checklist @checklist:kora_ambulance:hospital-bill @cat:police-and-ems
  Scenario: Hospital billing
    """
    Checklist test: Respawn at hospital: $500 base plus per-wound cost charged from cash then bank.
    """
    Given my cash balance is 1000
    And I am dead
    When I manually: wait for the respawn timer to end
    And I run the command "/respawn"
    Then I should see a notification containing "You were billed $"
    And I confirm: I was charged $500 base plus the per-wound cost, from cash first then bank

  @kora_ambulance @checklist @checklist:kora_ambulance:pharmacy @cat:police-and-ems
  Scenario: Hospital pharmacy shop
    """
    Checklist test: At a hospital pharmacy point open the shop and buy medical items.
    """
    Given my cash balance is at least 500
    When I manually: go to a hospital pharmacy point
    And I manually: open the pharmacy shop
    Then the "shop" inventory opens
    When I manually: buy a medical item from the shop
    Then I confirm: the bought medical item is added to my inventory and money is deducted

  @kora_ambulance @checklist @checklist:kora_ambulance:ems-stash @cat:police-and-ems
  Scenario: EMS stash
    """
    Checklist test: At the hospital stash point (on duty) open the shared stash and store/take items.
    """
    Given my job is "ambulance"
    And I am on duty
    And I have 1 "bandage"
    When I manually: go to the hospital stash point
    And I manually: open the shared stash
    Then the "stash" inventory opens
    When I manually: store the bandage in the stash
    Then I should have no "bandage"
    When I manually: take the bandage back out of the stash
    Then I should have 1 "bandage"

  @kora_ambulance @checklist @checklist:kora_ambulance:duty-vehicles @cat:police-and-ems
  Scenario: Duty vehicle garage
    """
    Checklist test: On duty at hospital garage: Check out Ambulance / Lifeguard ambulance / Response Bike; Return Vehicle stores it.
    """
    Given my job is "ambulance"
    And I am on duty
    When I manually: go to the hospital garage and open the EMS Garage menu
    And I manually: choose Check out Ambulance
    Then I should see a notification containing "Vehicle checked out."
    When I manually: choose Return Vehicle at the garage
    Then I should see a notification containing "Vehicle returned to the fleet."
    When I manually: repeat check out for Lifeguard ambulance and Response Bike, returning each
    Then I confirm: each vehicle spawns on checkout and is stored again on return

  @kora_ambulance @checklist @checklist:kora_ambulance:housecall-queue @cat:police-and-ems
  Scenario: House calls (/housecall /housecalls /accepthousecall)
    """
    Checklist test: Player /housecall <msg>; EMS /housecalls lists; /accepthousecall <id> sets waypoint.
    """
    Given my job is "ambulance"
    And I am on duty
    When I run the command "/housecalls"
    Then I confirm: the list of open house calls is shown, or a no-requests message appears
    When I manually: ask a second player to run /housecall with a message
    Then I confirm: the second player sees "Your request has been queued for EMS."
    When I run the command "/housecalls"
    Then I confirm: the new request is listed with its id
    When I manually: run /accepthousecall with the listed request id
    Then I should see a notification containing "accepted."
    And I confirm: a waypoint is set on my map to the caller

  @kora_ambulance @checklist @checklist:kora_ambulance:painkillers @cat:police-and-ems
  Scenario: Painkillers item
    """
    Checklist test: Use painkillers: pill animation with progress bar, +15 HP, 5 minute cooldown.
    """
    Given I have 1 "painkillers"
    And my health is 50%
    When I use a "painkillers"
    Then a progress bar should run
    And I confirm: a pill animation plays
    And I should see a notification containing "The pain dulls a little."
    And my "painkillers" count should have changed by -1
    And I confirm: my health increased by 15 HP
    When I use a "painkillers"
    Then I should see a notification containing "You took some recently"

  @kora_ambulance @checklist @checklist:kora_ambulance:ems-status-aheal @cat:police-and-ems
  Scenario: /status and /aheal
    """
    Checklist test: EMS runs /status for own health status; admin /aheal heals a player.
    """
    Given my job is "ambulance"
    When I run the command "/status"
    Then I should see a notification containing "Dead:"
    When I manually: ask a Mod to run /aheal with the id of an injured player
    Then I confirm: the other player is healed
    And I confirm: the Mod sees "Healed player"

  @kora_ambulance @checklist @checklist:kora_ambulance:hospital-blips @cat:police-and-ems @manual
  Scenario: Hospital map blips
    """
    Checklist test: Pillbox Hill and Sandy Shores hospital blips appear on the map under the Hospital category.
    """
    When I manually: open the map
    Then I confirm: a Pillbox Hill hospital blip appears under the Hospital category
    And I confirm: a Sandy Shores hospital blip appears under the Hospital category
