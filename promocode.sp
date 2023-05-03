#include <shop>

static const char alphabet[] = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

Database db;
char sPrefix[64];

public Plugin myinfo = 
{ 
	name = "[Shop] Promocode", 
	author = "Palonez", 
	description = "Promocode plugin for shop", 
	version = "1.0", 
	url = "https://github.com/Quake1011/" 
};

public void OnPluginStart()
{
	char sQuery[128];
	
	Shop_GetDatabasePrefix(sPrefix, sizeof(sPrefix));
	db = view_as<Database>(Shop_GetDatabase());
	
	if(db != null)
	{
		SQL_FormatQuery(db, sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `%s_promocode_users` (\
										`id` INTEGER(12) PRIMARY KEY,\
										`steam` VARCHAR(22) NOT NULL)", sPrefix);
		SQL_FastQuery(db, sQuery);

		SQL_FormatQuery(db, sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `%s_promocode` (\
												`id` INTEGER(12) NOT NULL AUTOINCREMENT,\
												`promocode` VARCHAR(64) PRIMARY KEY,\
												`count` INTEGER(12) NOT NULL,\
												`credits` INTEGER(12) NOT NULL)", sPrefix);
		SQL_FastQuery(db, sQuery);			
	}
	
	RegAdminCmd("sm_codegen", CodeGen, ADMFLAG_ROOT);
	RegAdminCmd("sm_delcode", DeleteCode, ADMFLAG_ROOT);
	RegAdminCmd("sm_promolist", PromoList, ADMFLAG_ROOT);
	RegConsoleCmd("sm_promocode", Promocode);
}

public Action Promocode(int client, int args)
{
	if(client >= 0 && client <= MaxClients)
		return Plugin_Handled;

	if(args < 1 || args > 1)
		return Plugin_Handled;
		
	char arg[64], sQuery[256];
	GetCmdArg(1, arg, sizeof(arg));
	
	SQL_FormatQuery(db, sQuery, sizeof(sQuery), "SELECT * FROM `%s_promocode` WHERE `promocode` = '%s'", sPrefix, arg);
	db.Query(SQLSendPromoCode, sQuery, client, DBPrio_High);

	return Plugin_Handled;
}

public void SQLSendPromoCode(Database hdb, DBResultSet results, const char[] error, int client)
{
	if(hdb == null || !error[0])
	{
		SetFailState("%s", error);
		return;
	}

	if(results != INVALID_HANDLE)
	{
		if(results.HasResults && results.RowCount == 1)
		{
			if(results.FetchRow())
			{
				char sAuth[22], sQuery[256];
				GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
				SQL_FormatQuery(db, sQuery, sizeof(sQuery), "SELECT * FROM `%s_promocode_users` WHERE `id` = '%d' AND `steam` = '%s'", sPrefix, results.FetchInt(0), sAuth);
				DataPack dp = CreateDataPack();
				dp.WriteCell(results.FetchInt(0));
				dp.WriteCell(client);
				dp.WriteCell(results.FetchInt(3));
				db.Query(SQLCheckUsedUser, sQuery, dp, DBPrio_High);
				delete dp;
			}
		}
	}
}

public void SQLCheckUsedUser(Database hdb, DBResultSet results, const char[] error, any hdp)
{
	DataPack dp = view_as<DataPack>(hdp);
	dp.Reset();
	
	int id = dp.ReadCell();
	int client = dp.ReadCell();
	int credits = dp.ReadCell();
	
	delete dp;

	if(hdb == null || !error[0])
	{
		SetFailState("%s", error);
		return;
	}
	
	if(results != INVALID_HANDLE)
	{
		if(results.HasResults && !results.RowCount)
		{
			if(!results.RowCount)
			{
				char sQuery[256];
				if(results.FetchInt(2) == 1) SQL_FormatQuery(db, sQuery, sizeof(sQuery), "DELETE FROM `%s_promocode` WHERE `id` = '%d'",sPrefix, id);
				else if(results.FetchInt(2) > 1) SQL_FormatQuery(db, sQuery, sizeof(sQuery), "UPDATE `%s_promocode` SET `count` = `count` - 1 WHERE `id` = '%d'", sPrefix, id);
				SQL_FastQuery(db, sQuery);
				
				Shop_GiveClientCredits(client, results.FetchInt(3));
				PrintToChat(client, "Promocode successfully activated! Reward %d credits", credits);		
			}
			else PrintToChat(client, "Promocode already activated");
		}
	}
}

public Action PromoList(int client, int args)
{
	if(client >= 0 && client <= MaxClients)
		return Plugin_Handled;

	OpenList(client);
	
	return Plugin_Handled;
}

void OpenList(int client)
{
	char sQuery[256];
	SQL_FormatQuery(db, sQuery, sizeof(sQuery), "SELECT * FROM `%s_promocode`", sPrefix);
	db.Query(SQLQueryList, sQuery, client, DBPrio_High);
}

public void SQLQueryList(Database hdb, DBResultSet results, const char[] error, int client)
{
	if(hdb == null || !error[0])
	{
		SetFailState("%s", error);
		return;
	}

	if(results != INVALID_HANDLE)
	{
		if(results.HasResults && results.RowCount > 0)
		{
			if(results.FetchRow())
			{
				Menu hMenu = CreateMenu(Handler);
				hMenu.SetTitle("PromoList");
				char sCode[64], buffer[128];
				int iCount, iCredits;
				do
				{
					results.FetchString(1, sCode, sizeof(sCode));
					iCount = results.FetchInt(2);
					iCredits = results.FetchInt(3);
					Format(buffer, sizeof(buffer), "%s (x%d) - %d credits", sCode, iCount, iCredits);
					hMenu.AddItem(buffer, buffer);
				} while(results.FetchRow());
				
				hMenu.ExitBackButton = true;
				hMenu.ExitButton = true;
				
				hMenu.Display(client, 0);
			}
		}
	}
}

public int Handler(Menu hMenu, MenuAction action, int client, int item)
{
	switch(action)
	{
		case MenuAction_End: delete hMenu;
		case MenuAction_Select: OpenList(client);
	}
	return 0;
}

public Action DeleteCode(int client, int args)
{
	if(client >= 0 && client <= MaxClients)
		return Plugin_Handled;
	
	if(!args) 
	{
		ReplyToCommand(client, "Use: \"sm_delcode <code string>\"");		
		return Plugin_Handled;
	}

	char arg[128], sQuery[256];
	GetCmdArg(1, arg, sizeof(arg));
	SQL_FormatQuery(db, sQuery, sizeof(sQuery), "DELETE FROM `%s_promocode` WHERE `promocode` = '%s'", sPrefix, arg);
	db.Query(SQLQueryCallBack, sQuery, _, DBPrio_High);
	
	return Plugin_Handled;
}

public Action CodeGen(int client, int args)
{
	if(client >= 0 && client <= MaxClients)
		return Plugin_Handled;
	
	if(args < 3 || args > 4) 
	{
		ReplyToCommand(client, "Use: \"sm_codegen <code string> <count> <credits>\" or \"sm_codegen \"random\" <length> <count> <credits>\"");	
		return Plugin_Handled;
	}

	char arg[128], counts[12], crds[12];
	GetCmdArg(1, arg, sizeof(arg));
	
	TrimString(arg);
	
	if(strlen(arg) > 64 && strlen(arg) < 2)
	{
		ReplyToCommand(client, "Length of the promocode should vary from 2 to 64 characters");	
		return Plugin_Handled;
	}

	GetCmdArg(3, counts, sizeof(counts));
	GetCmdArg(4, crds, sizeof(crds));
	
	if(StringToInt(crds) < 0 || StringToInt(counts) < 0)
	{
		ReplyToCommand(client, "Values of count or credits cant be less then 0");	
		return Plugin_Handled;
	}
	
	if(StrEqual("random", arg))
	{
		if(args == 4)
		{
			char length[12], sQuery[256];
			GetCmdArg(2, length, sizeof(length));	
			
			if(StringToInt(length) > 64 && StringToInt(length) < 2)
			{
				ReplyToCommand(client, "Length of the promocode should vary from 2 to 64 characters");		
				return Plugin_Handled;
			}
			
			char[] code = new char[StringToInt(length)];	
			for(int i = 0; i < StringToInt(length); i++)
				code[i] = alphabet[GetRandomInt(0, sizeof(alphabet) - 1)];

			SQL_FormatQuery(db, sQuery, sizeof(sQuery), "INSERT INTO `%s_promocode` (`promocode`, `count`, `credits`) VALUES ('%s', '%d', '%d')", sPrefix, code, StringToInt(counts), StringToInt(crds));
			db.Query(SQLQueryCallBack, sQuery, _, DBPrio_High);
		}
	}
	else if(args == 3)
	{
		char sQuery[256];
		SQL_FormatQuery(db, sQuery, sizeof(sQuery), "INSERT INTO `%s_promocode` (`promocode`, `count`, `credits`) VALUES ('%s', '%d', '%d')", sPrefix, arg, StringToInt(counts), StringToInt(crds));
		db.Query(SQLQueryCallBack, sQuery, _, DBPrio_High);
	}

	return Plugin_Handled;
}

public void SQLQueryCallBack(Database hdb, DBResultSet results, const char[] error, any data)
{
	if(hdb == null || !error[0])
	{
		SetFailState("%s", error);
		return;
	}
}