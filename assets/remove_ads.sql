DELETE FROM favorites
WHERE appWidgetProvider LIKE 'com.mumu.store/%'
   OR intent LIKE '%component=com.mumu.store/.MainActivity%'
   OR intent LIKE '%component=com.mumu.store/%';

SELECT _id, title, appWidgetProvider, intent FROM favorites ORDER BY _id;
