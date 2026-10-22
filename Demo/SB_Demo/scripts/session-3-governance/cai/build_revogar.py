"""Derives p_SB_MP_Revogar from the p_SB_MP_Atender package (same proven structure).

Flow (one access per run):
  GET consumerAccess?status=PENDING_WITHDRAW
  -> first access object: "id": "<uuid>", "refId": "ACC-n", "status": "PENDING_WITHDRAW"
  -> none: "Sin retiros pendientes"
  -> found: Snowflake STUB (block C of script 05) + PUT consumerAccess/{{consumerAccessId}}/withdrawn
Usage: python3 build_revogar.py <atender_zip> <out_zip>
"""
import hashlib, json, re, sys, zipfile
from datetime import datetime, timezone

SRC, OUT = sys.argv[1], sys.argv[2]
P_OLD = "Explore/Rest Accelerator/p_SB_MP_Atender.PROCESS.xml"
P_NEW = "Explore/Rest Accelerator/p_SB_MP_Revogar.PROCESS.xml"
zin = zipfile.ZipFile(SRC)
x = zin.read(P_OLD).decode()
meta = json.loads(zin.read("exportMetadata.v2.json"))
proj_json = zin.read("Explore/Rest Accelerator.Project.json")

OLD_GUID, NEW_GUID = "5bSBmpAtenderPedidos01", "5bSBmpRevogarAccesos01"
RX_ACC_TEST = r'"id"\s*:\s*"[^"]+"\s*,\s*"refId"\s*:\s*"ACC-[^"]*"\s*,\s*"status"\s*:\s*"PENDING_WITHDRAW"'
RX_ACC = r'^.*?"id"\s*:\s*"([^"]+)"\s*,\s*"refId"\s*:\s*"ACC-[^"]*"\s*,\s*"status"\s*:\s*"PENDING_WITHDRAW".*$'
RX_REF = r'^.*?"id"\s*:\s*"[^"]+"\s*,\s*"refId"\s*:\s*"(ACC-[^"]*)"\s*,\s*"status"\s*:\s*"PENDING_WITHDRAW".*$'


def sub(old, new, count=1):
    global x
    assert x.count(old) >= count, old[:80]
    x = x.replace(old, new)


sub(OLD_GUID, NEW_GUID, 3)
sub("p_SB_MP_Atender", "p_SB_MP_Revogar", 3)
sub("Demo SB C08-AE-07: atiende el primer pedido APROBADO de DCL-4 (Snowflake stub + fulfill).",
    "Demo SB C08-AE-08: revoca el primer acceso con retiro pendiente (Snowflake stub + withdrawn).")
sub("Demo SB C08-AE-07: fulfill automatico de pedidos aprobados.",
    "Demo SB C08-AE-08: revocacion automatica de accesos.")
sub("Cada ejecucion atiende un pedido.", "Cada ejecucion revoca un acceso.")
sub('description="1 = hay pedido aprobado" name="Temp_Hay_Pedido"', 'description="1 = hay retiro pendiente" name="Temp_Hay_Pedido"')

# 1) query: pending withdrawals
x = re.sub(r"(<title>Preparar consulta pedidos aprobados</title>\s*<operation[^>]*>\s*<expression language=\"XQuery\">).*?(</expression>)",
           lambda m: m.group(1) + "&lt;DataMarketplaceQueryParameters&gt;&lt;queryParams&gt;&lt;value&gt;PENDING_WITHDRAW&lt;/value&gt;&lt;name&gt;status&lt;/name&gt;&lt;/queryParams&gt;&lt;/DataMarketplaceQueryParameters&gt;" + m.group(2),
           x, count=1, flags=re.S)
sub("Preparar consulta pedidos aprobados", "Preparar consulta retiros pendientes")
sub("<title>Listar pedidos aprobados</title>", "<title>Listar retiros pendientes</title>")
sub('<parameter name="relativePath" source="constant">orders</parameter>',
    '<parameter name="relativePath" source="constant">consumerAccess</parameter>')

# 2) extraction: access id (Temp_OrderId) and ACC ref (Temp_TargetId)
x = re.sub(r'(to="temp.Temp_Hay_Pedido">\s*<expression language="XQuery">).*?(</expression>)',
           lambda m: m.group(1) + f"if (matches(string($temp.Temp_Response), '{RX_ACC_TEST}', 's')) then 1 else 0" + m.group(2), x, count=1, flags=re.S)
x = re.sub(r'(to="temp.Temp_OrderId">\s*<expression language="XQuery">).*?(</expression>)',
           lambda m: m.group(1) + f"if (matches(string($temp.Temp_Response), '{RX_ACC_TEST}', 's')) then replace(string($temp.Temp_Response), '{RX_ACC}', '$1', 's') else ''" + m.group(2), x, count=1, flags=re.S)
x = re.sub(r'(to="temp.Temp_TargetId">\s*<expression language="XQuery">).*?(</expression>)',
           lambda m: m.group(1) + f"if (matches(string($temp.Temp_Response), '{RX_ACC_TEST}', 's')) then replace(string($temp.Temp_Response), '{RX_REF}', '$1', 's') else ''" + m.group(2), x, count=1, flags=re.S)
sub("<title>Extraer pedido y destino</title>", "<title>Extraer acceso</title>")
sub("<title>Hay pedido aprobado?</title>", "<title>Hay retiro pendiente?</title>")

# 3) Snowflake stub = block C; fulfill call -> withdrawn
x = re.sub(r'(<title>Snowflake STUB \(bloque A script 05\)</title>\s*<operation[^>]*>\s*<expression language="XQuery">).*?(</expression>)',
           lambda m: m.group(1) + "concat('ALTER USER EXT_ANALISTA_PYME SET DISABLED = TRUE; REVOKE ROLE FR_EXTERNAL_READER FROM USER EXT_ANALISTA_PYME; -- acceso ', $temp.Temp_TargetId)" + m.group(2),
           x, count=1, flags=re.S)
sub("Snowflake STUB (bloque A script 05)", "Snowflake STUB (bloque C script 05)")
x = re.sub(r'(<title>Snowflake STUB \(bloque C script 05\)</title>.*?to="temp.Temp_Query_Params">\s*<expression language="XQuery">).*?(</expression>)',
           lambda m: m.group(1) + "&lt;DataMarketplaceQueryParameters&gt;&lt;queryParams&gt;&lt;value&gt;Acceso revocado automaticamente por CAI (usuario Snowflake deshabilitado)&lt;/value&gt;&lt;name&gt;comment&lt;/name&gt;&lt;/queryParams&gt;&lt;/DataMarketplaceQueryParameters&gt;" + m.group(2),
           x, count=1, flags=re.S)
sub("&lt;name&gt;orderId&lt;/name&gt;", "&lt;name&gt;consumerAccessId&lt;/name&gt;")
sub("<title>Fulfill pedido</title>", "<title>Revocar acceso (withdrawn)</title>")
sub('<parameter name="relativePath" source="constant">orders/{{orderId}}/fulfill</parameter>',
    '<parameter name="relativePath" source="constant">consumerAccess/{{consumerAccessId}}/withdrawn</parameter>')
sub("<title>Resultado atendido</title>", "<title>Resultado revocado</title>")
sub("concat('Pedido ', $temp.Temp_OrderId, ' atendido (destino ', $temp.Temp_TargetId, '). Snowflake STUB: ', $temp.Temp_Snowflake_SQL)",
    "concat('Acceso ', $temp.Temp_TargetId, ' (', $temp.Temp_OrderId, ') revocado. Snowflake STUB: ', $temp.Temp_Snowflake_SQL)")
sub("'Sin pedidos aprobados pendientes en DCL-4'", "'Sin retiros pendientes'")
sub("<title>Sin pedidos</title>", "<title>Sin retiros</title>")
x = x.replace("lSBat", "lSBrv").replace("SBat", "SBrv")

for o in meta["exportedObjects"]:
    if o["objectType"] == "PROCESS":
        o.update(objectGuid=NEW_GUID, objectName="p_SB_MP_Revogar")
        o["metadata"]["repoInfo"]["repoHandle"] = f"{NEW_GUID}::pd.xml"
        o["metadata"]["additionalInfo"]["description"] = "Demo SB C08-AE-08"
    proj_guid = o["objectGuid"] if o["objectType"] == "Project" else None
meta["name"] = "p_SB_MP_Revogar"
files = {P_NEW: x.encode(), "Explore/Rest Accelerator.Project.json": proj_json,
         "exportMetadata.v2.json": json.dumps(meta, indent=2).encode()}
pg = next(o["objectGuid"] for o in meta["exportedObjects"] if o["objectType"] == "Project")
files["ContentsofExportPackage_p_SB_MP_Revogar.csv"] = (
    f"objectPath,objectName,objectType,id\n/Explore/Rest Accelerator,p_SB_MP_Revogar,PROCESS,{NEW_GUID}\n"
    f"/Explore,Rest Accelerator,Project,{pg}\n").encode()
chk = "#\n#" + datetime.now(timezone.utc).strftime("%a %b %d %H:%M:%S UTC %Y") + "\n"
for k in ("exportMetadata.v2.json", P_NEW, "Explore/Rest Accelerator.Project.json"):
    chk += k.replace(" ", "\\ ") + "=" + hashlib.sha256(files[k]).hexdigest().upper() + "\n"
files["exportPackage.chksum"] = chk.encode()
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    for k, v in files.items():
        z.writestr(k, v)
print("ok", OUT)
