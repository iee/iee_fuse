#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>

#include <json-c/json.h>

int main(int argc, char **argv)
{
  struct json_object *new_obj, *next_obj, *next_obj_page;

  MC_SET_DEBUG(1);
  // I added some new lines... not in real program
  new_obj = json_tokener_parse("/* more difficult test case */ { \"glossary\": { \"title\": \"example glossary\", \"pageCount\": 100, \"GlossDiv\": { \"title\": \"S\", \"GlossList\": [ { \"ID\": \"SGML\", \"SortAs\": \"SGML\", \"GlossTerm\": \"Standard Generalized Markup Language\", \"Acronym\": \"SGML\", \"Abbrev\": \"ISO 8879:1986\", \"GlossDef\": \"A meta-markup language, used to create markup languages such as DocBook.\", \"GlossSeeAlso\": [\"GML\", \"XML\", \"markup\"] } ] } } }");
  //printf("new_obj.to_string()=%s\n", json_object_to_json_string(new_obj));
  
  json_object_object_get_ex(new_obj, "glossary", &next_obj);
  json_object_object_get_ex(new_obj, "glossary", &next_obj_page);
  printf("new_obj.to_string()=%s\n", json_object_to_json_string(next_obj));
  json_object_object_get_ex(next_obj, "GlossDiv", &next_obj);
  json_object_object_get_ex(next_obj, "title", &next_obj);
  printf("new_obj.to_string()=%s\n", json_object_get_string(next_obj));

  json_object_object_get_ex(next_obj_page, "pageCount", &next_obj);


  int pageCount = json_object_get_int64(next_obj);

  printf("Page count = %d\n", pageCount);

  json_object_put(new_obj);

  return 0;
}