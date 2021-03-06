#define SAVE_RESET -1

/datum/preferences
	//doohickeys for savefiles
	var/path
	var/default_slot = 1				//Holder so it doesn't default to slot 1, rather the last one used
	var/savefile_version = 0

	//non-preference stuff
	var/warns = 0
	var/muted = 0
	var/last_ip
	var/last_id

	var/save_load_cooldown

	//game-preferences
	var/lastchangelog = ""				//Saved changlog filesize to detect if there was a change

	var/list/time_of_death = list()//This is a list of last times of death for various things with different respawn timers

	var/list/crew_respawn_bonuses = list()
	//This is a list of bonuses that are subtracted from your crew respawn time
	//This is used to make certain ingame actions allow a dead player to respawn faster
	//It uses an associative list to prevent exploits, so the same bonus cannot be gained repeatedly.
	//It will just overwrite the value

	var/client/client = null
	var/client_ckey = null

	var/savefile/loaded_preferences
	var/savefile/loaded_character
	var/datum/category_collection/player_setup_collection/player_setup
	var/datum/browser/panel

	var/fullscreen = FALSE

/datum/preferences/New(client/C)
	if(istype(C))
		client = C
		client_ckey = C.ckey
		SScharacter_setup.preferences_datums += src
		if(SScharacter_setup.initialized)
			setup()
		else
			SScharacter_setup.prefs_awaiting_setup += src
	..()

/datum/preferences/proc/setup()
//	if(!length(GLOB.skills))
//		decls_repository.get_decl(/decl/hierarchy/skill)
	player_setup = new(src)
	gender = pick(MALE, FEMALE)
	real_name = random_name(gender,species)
	b_type = RANDOM_BLOOD_TYPE

	if(client && !IsGuestKey(client.key))
		load_path(client.ckey)
		load_preferences()
		load_and_update_character()

	sanitize_preferences()
	if(client && istype(client.mob, /mob/new_player))
		var/mob/new_player/np = client.mob
		np.new_player_panel(TRUE)

/datum/preferences/proc/load_and_update_character(var/slot)
	load_character(slot)
	if(update_setup(loaded_preferences, loaded_character))
		save_preferences()
		save_character()

/datum/preferences/proc/ShowChoices(mob/user)
	if(!SScharacter_setup.initialized)
		return
	if(!user || !user.client)
		return

	if(!get_mob_by_key(client_ckey))
		to_chat(user, SPAN_DANGER("No mob exists for the given client!"))
		close_load_dialog(user)
		return

	if(!path && !IsGuestKey(user.client.key))
		error("Prefs failed to setup (datum): [user.client.ckey]")
		load_path(user.client.ckey)
		load_preferences()
		load_and_update_character()

	var/dat = "<html><body><center>"

	if(path)
//		dat += "Слот - "
//		dat += "<a href='?src=\ref[src];load=1'>Загрузить</a> - "
		dat += "<a href='?src=\ref[src];save=1'>Сохранить персонажа</a> "
		dat += "<a href='?src=\ref[src];resetslot=1'>Сбросить персонажа</a>"
//		dat += "<a href='?src=\ref[src];reload=1'>Перезагрузить</a>"

	else
		dat += "Please create an account to save your preferences."

	dat += "<br>"
	dat += player_setup.header()
	dat += "<br><HR></center>"
	dat += player_setup.content(user)

	dat += "</html></body>"
	var/datum/browser/popup = new(user, "Настройка персонажа","Настройка персонажа", 800, 850, src)
	popup.set_content(dat)
	popup.open()

/datum/preferences/proc/process_link(mob/user, list/href_list)

	if(!user)	return
	if(isliving(user)) return

	if(href_list["preference"] == "open_whitelist_forum")
		if(config.forumurl)
			user << link(config.forumurl)
		else
			to_chat(user, SPAN_DANGER("The forum URL is not set in the server configuration."))
			return
	ShowChoices(usr)
	return 1

/datum/preferences/proc/check_cooldown()
	if(save_load_cooldown != world.time && (save_load_cooldown + PREF_SAVELOAD_COOLDOWN > world.time))
		return FALSE

	save_load_cooldown = world.time
	return TRUE


/datum/preferences/Topic(href, list/href_list)
	if(..())
		return 1

	if(href_list["save"])
		if(!char_exists)
			var/response = alert("В случае, если вы сохраните его, у вас больше не будет возможности менять его имя и внешность!","Вы уверены, что хотите сохранить персонажа?","Нет","Да")
			if(response == "Нет")
				return
		char_exists = 1
		save_preferences()
		save_character()
//	else if(href_list["reload"])
//		load_preferences()
//		load_character()
//		sanitize_preferences()
	else if(href_list["load"])
		if(!IsGuestKey(usr.key))
			open_load_dialog(usr)
			return 1
	else if(href_list["changeslot"])
		load_character(text2num(href_list["changeslot"]))
		sanitize_preferences()
		close_load_dialog(usr)
	else if(href_list["chooseslot"])
		load_character(text2num(href_list["chooseslot"]))
		sanitize_preferences()
		close_load_dialog(usr)
		return 1
	else if(href_list["resetslot"])
		for(var/mob/living/carbon/human/R in SSmobs.mob_list)
			if(client.prefs.character_id == R.character_id)
				to_chat(usr, "You can't reset character that is already in-game!")
				return 0
		if(real_name != input("Это сбросит текущий слот и разблокирует его редактирование, однако вы потеряете все свои сбережения! Введите имя персонажа чтобы продолжить."))
			return 0
		reset_character()
		sanitize_preferences()
	else if(href_list["close_load_dialog"])
		close_load_dialog(usr)
		return 1
	else
		return 0

	ShowChoices(usr)
	return 1

/datum/preferences/proc/copy_to(mob/living/carbon/human/character, is_preview_copy = FALSE)
	// Sanitizing rather than saving as someone might still be editing when copy_to occurs.
	player_setup.sanitize_setup()
	character.set_species(species)

//	if(be_random_name)
//		real_name = random_name(gender,species)

	if(config.humans_need_surnames)
		var/firstspace = findtext(real_name, " ")
		var/name_length = length(real_name)
		if(!firstspace)	//we need a surname
			real_name += " [pick(GLOB.last_names)]"
		else if(firstspace == name_length)
			real_name += "[pick(GLOB.last_names)]"
	character.fully_replace_character_name(newname = real_name)
	character.gender = gender
	character.age = age
	character.b_type = b_type

	character.h_style = h_style
	character.f_style = f_style

	// Build mob body from prefs
	character.rebuild_organs(src)

	character.eyes_color = eyes_color
	character.hair_color = hair_color
	character.facial_color = facial_color
	character.skin_color = skin_color

	character.s_tone = s_tone

	QDEL_NULL_LIST(character.worn_underwear)
	character.worn_underwear = list()

	for(var/underwear_category_name in all_underwear)
		var/datum/category_group/underwear/underwear_category = GLOB.underwear.categories_by_name[underwear_category_name]
		if(underwear_category)
			var/underwear_item_name = all_underwear[underwear_category_name]
			var/datum/category_item/underwear/UWD = underwear_category.items_by_name[underwear_item_name]
			var/metadata = all_underwear_metadata[underwear_category_name]
			var/obj/item/underwear/UW = UWD.create_underwear(character, metadata, 'icons/inventory/underwear/mob.dmi')
			if(UW)
				UW.ForceEquipUnderwear(character, FALSE)
		else
			all_underwear -= underwear_category_name

	character.backpack_setup = new(backpack, backpack_metadata["[backpack]"])

	character.force_update_limbs()
	character.update_mutations(0)
	character.update_implants(0)


	character.update_body(0)
	character.update_underwear(0)

	character.update_hair(0)

	character.update_icons()

	if(is_preview_copy)
		return

	for(var/lang in alternate_languages)
		character.add_language(lang)

	character.med_record = med_record
	character.sec_record = sec_record
	character.gen_record = gen_record
	character.exploit_record = exploit_record
	if(!character.isSynthetic())
		character.nutrition = rand(250, 450)

	for(var/options_name in setup_options)
		get_option(options_name).apply(character)


/datum/preferences/proc/open_load_dialog(mob/user)
	var/dat  = list()
	dat += "<body>"
	dat += "<tt><center>"

	var/savefile/S = new /savefile(path)
	if(S)
		dat += "<b>Выберите вашего персонажа</b><br>"
		dat += "Для редактирования нажмите [WRENCH_ICON]<hr>"
		var/name
		for(var/i=1, i<= config.character_slots, i++)
			S.cd = maps_data.character_load_path(S, i)
			S["real_name"] >> name
//			if(!name)	name = "Создать"
//			if(i==default_slot)
//				name = "<b>[name]</b>"
			if(name && i==default_slot)
				dat += "<b>[name]</b> <a href='?src=\ref[src];changeslot=[i]'>[WRENCH_ICON]</a><br>"
			else if(name && i!=default_slot)
				dat += "<a href='?src=\ref[src];chooseslot=[i]'>[name]</a><a href='?src=\ref[src];changeslot=[i]'>[WRENCH_ICON]</a><br>"
			else if(!name)
				dat += "<a href='?src=\ref[src];changeslot=[i]'>Создать нового</a><br>"

	dat += "<hr>"
	dat += "<a href='?src=\ref[src];close_load_dialog=1'>Закрыть</a><br>"
	dat += "</center></tt>"
	panel = new(user, "Слоты персонажей", "Слоты персонажей", 250, 280, src)
	panel.set_window_options("can_close=0;can_resize=0;window=saves")
	panel.set_content(jointext(dat,null))
	panel.open()

/datum/preferences/proc/close_load_dialog(mob/user)
	if(panel)
		panel.close()
		panel = null
	user << browse(null, "window=saves")