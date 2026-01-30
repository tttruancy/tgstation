/// Visual Scramble status effect - scrambles tiles visually and garbles names
/datum/status_effect/visual_scramble
	id = "visual_scramble"
	status_type = STATUS_EFFECT_REPLACE
	alert_type = /atom/movable/screen/alert/status_effect/visual_scramble
	remove_on_fullheal = TRUE
	tick_interval = 4 SECONDS  // Re-scramble every 4 seconds (backup in case movement signal fails)
	/// Outer radius of turfs to scramble around the player
	var/scramble_radius = 7
	/// Inner radius - turfs within this distance are NOT scrambled (creates unscrambled area around player)
	var/inner_radius = 2
	/// List of alternate appearance datums we've created, for cleanup
	var/list/datum/atom_hud/alternate_appearance/scrambled_appearances = list()
	/// List of turfs and their appearance keys for cleanup
	var/list/turf/scrambled_turfs = list()

/datum/status_effect/visual_scramble/on_creation(mob/living/new_owner, duration = 10 SECONDS)
	src.duration = duration
	return ..()

/datum/status_effect/visual_scramble/on_apply()
	RegisterSignal(owner, COMSIG_LIVING_DEATH, PROC_REF(remove_visual_scramble))
	RegisterSignal(owner, COMSIG_MOB_LOGIN, PROC_REF(update_scramble))
	RegisterSignal(owner, COMSIG_MOVABLE_MOVED, PROC_REF(on_mob_moved))
	RegisterSignal(owner, COMSIG_LIVING_PERCEIVE_EXAMINE_NAME, PROC_REF(garble_examine_name))

	// Apply initial visual scrambling
	update_scramble()
	return TRUE

/datum/status_effect/visual_scramble/on_remove()
	UnregisterSignal(owner, list(
		COMSIG_LIVING_DEATH,
		COMSIG_MOB_LOGIN,
		COMSIG_MOVABLE_MOVED,
		COMSIG_LIVING_PERCEIVE_EXAMINE_NAME
	))

	// Clean up all alternate appearances
	clear_scrambled_appearances()

/datum/status_effect/visual_scramble/tick(seconds_between_ticks)
	// Periodically re-scramble to create dynamic effect
	update_scramble()

/// Removes visual scramble on death
/datum/status_effect/visual_scramble/proc/remove_visual_scramble(datum/source, admin_revive)
	SIGNAL_HANDLER
	qdel(src)

/// Called when the mob moves - re-scramble the view
/datum/status_effect/visual_scramble/proc/on_mob_moved(atom/movable/moved, atom/old_loc, movement_dir, forced, list/old_locs, momentum_change)
	SIGNAL_HANDLER
	// Only re-scramble if we actually changed turfs
	var/turf/old_turf = get_turf(old_loc)
	var/turf/new_turf = get_turf(moved)
	if(old_turf != new_turf)
		update_scramble()

/// Clears all scrambled appearances
/datum/status_effect/visual_scramble/proc/clear_scrambled_appearances()
	// Remove alternate appearances from turfs using stored keys
	for(var/turf/scrambled_turf in scrambled_turfs)
		var/appearance_key = scrambled_turfs[scrambled_turf]
		scrambled_turf.remove_alt_appearance(appearance_key)

	// Clean up datums
	for(var/datum/atom_hud/alternate_appearance/appearance_datum in scrambled_appearances)
		qdel(appearance_datum)

	scrambled_appearances.Cut()
	scrambled_turfs.Cut()

/// Updates the visual scramble by swapping turf appearances
/// Uses alternate appearances with photograph() to swap what turfs look like
/datum/status_effect/visual_scramble/proc/update_scramble(datum/source)
	SIGNAL_HANDLER

	if(!owner || !owner.client)
		return

	// Clear existing scrambled appearances
	clear_scrambled_appearances()

	var/turf/center_turf = get_turf(owner)
	if(!center_turf)
		return

	// Get all turfs within scramble radius, but exclude those within inner_radius (safe zone)
	var/list/turf/turfs_to_scramble = list()
	for(var/turf/check_turf in spiral_range_turfs(scramble_radius, center_turf))
		var/distance = get_dist(center_turf, check_turf)
		// Only scramble turfs beyond the inner radius
		if(distance > inner_radius)
			turfs_to_scramble += check_turf

	if(!length(turfs_to_scramble))
		return

	// Create pairs of turfs to swap visually
	var/list/turf_swaps = list()
	var/num_to_scramble = round(length(turfs_to_scramble) * 0.5)

	for(var/i in 1 to num_to_scramble)
		if(!length(turfs_to_scramble))
			break
		var/turf/swap_a = pick_n_take(turfs_to_scramble)
		if(!length(turfs_to_scramble))
			break
		var/turf/swap_b = pick_n_take(turfs_to_scramble)
		turf_swaps[swap_a] = swap_b
		turf_swaps[swap_b] = swap_a

	// If there's an odd turf left, pair it with a random one
	if(length(turfs_to_scramble))
		var/turf/loner = pick(turfs_to_scramble)
		var/turf/random_partner = pick(turf_swaps)
		turf_swaps[loner] = random_partner
		turf_swaps[random_partner] = loner

	// Create alternate appearances for each swapped pair
	for(var/turf/target_turf in turf_swaps)
		var/turf/swapped_turf = turf_swaps[target_turf]

		// Get the photograph of the turf we want to show
		var/image/turf_image = swapped_turf.photograph()
		turf_image.loc = target_turf  // Set loc so it displays on the target turf

		// Create alternate appearance that only the owner can see
		var/appearance_key = "visual_scramble_[target_turf.x]_[target_turf.y]_[target_turf.z]"

		// add_alt_appearance creates the datum and returns it
		var/datum/atom_hud/alternate_appearance/appearance_datum = target_turf.add_alt_appearance(
			/datum/atom_hud/alternate_appearance/basic/one_person,
			appearance_key,
			turf_image,
			NONE,  // Options - NONE means target doesn't see their own appearance
			owner
		)

		// Store for cleanup
		if(appearance_datum)
			scrambled_appearances += appearance_datum
			scrambled_turfs[target_turf] = appearance_key

/// Garbles names when examining
/// Signal: COMSIG_LIVING_PERCEIVE_EXAMINE_NAME
/// Parameters: (mob/examined, visible_name, list/name_override)
/datum/status_effect/visual_scramble/proc/garble_examine_name(datum/source, mob/examined, visible_name, list/name_override)
	SIGNAL_HANDLER

	// Don't garble our own name
	if(source == examined)
		return NONE

	// Only garble living mobs (the signal is only sent for living mobs anyway)
	if(!isliving(examined))
		return NONE

	name_override[1] = garble_name(visible_name)
	return COMPONENT_EXAMINE_NAME_OVERRIDEN

/// Converts a name string to garbled nonsense
/// Uses a deterministic approach so the same name always garbles to the same gibberish
/datum/status_effect/visual_scramble/proc/garble_name(text)
	if(!text || text == "Unknown")
		return text

	// Use the text as a seed for deterministic scrambling
	var/seed = 0
	for(var/i in 1 to length(text))
		seed += text2ascii(text, i) * i

	// Generate garbled text maintaining similar length
	var/garbled = ""
	var/list/consonants = list("b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "q", "r", "s", "t", "v", "w", "x", "z")
	var/list/vowels = list("a", "e", "i", "o", "u", "y")

	// Preserve spaces and punctuation
	for(var/i in 1 to length(text))
		var/char = text[i]
		if(char == " " || char == "-" || char == "'")
			garbled += char
			continue

		// Use seeded random for deterministic scrambling
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var/rand_val = (seed >> 16) & 0x7fff

		// Alternate between consonants and vowels to make it look like a language
		// Use seeded random (rand_val % 100) instead of prob()
		if(length(garbled) == 0 || (rand_val % 100) < 60)
			seed = (seed * 1103515245 + 12345) & 0x7fffffff
			rand_val = (seed >> 16) & 0x7fff
			garbled += consonants[(rand_val % length(consonants)) + 1]
		else
			seed = (seed * 1103515245 + 12345) & 0x7fffffff
			rand_val = (seed >> 16) & 0x7fff
			garbled += vowels[(rand_val % length(vowels)) + 1]

		// Occasionally add a consonant-vowel pair
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		rand_val = (seed >> 16) & 0x7fff
		if((rand_val % 100) < 30)
			seed = (seed * 1103515245 + 12345) & 0x7fffffff
			rand_val = (seed >> 16) & 0x7fff
			garbled += vowels[(rand_val % length(vowels)) + 1]

	// Capitalize first letter if original was capitalized
	// Uppercase letters are ASCII 65-90 (A-Z)
	if(length(text) > 0)
		var/first_char_ascii = text2ascii(text, 1)
		if(first_char_ascii >= 65 && first_char_ascii <= 90)
			garbled = capitalize(garbled)

	return garbled

/// Status effect alert
/atom/movable/screen/alert/status_effect/visual_scramble
	name = "Visual Scramble"
	desc = "Your vision is scrambled and names appear as garbled nonsense!"
	use_user_hud_icon = TRUE
	overlay_state = "visual_scramble"

