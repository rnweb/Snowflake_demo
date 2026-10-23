"""Builds an IDMC (CAI) import package with p_SB_MP_Atender.

Flow (one approved order per run; schedule it to drain the queue):
  GET orders?dataCollectionIds=<DCL-4>&status=APPROVED
  -> take the first order id + its requestedProvisionedTargetRef (delivery target)
  -> none: output "sin pedidos aprobados" and end
  -> found: Snowflake provisioning (STUB until the new account exists)
            PUT orders/{{orderId}}/fulfill?deliveryTargetId=..&comment=..
Usage: python3 build.py <accelerator_orders_dir> <out_zip>
"""
import hashlib, json, os, shutil, sys, zipfile
from datetime import datetime, timezone

SRC, OUT = sys.argv[1], sys.argv[2]
DCL = "48b1714b-f264-4510-b087-a7b666aa3c62"
GUID = "5bSBmpAtenderPedidos01"          # 22 chars, base62 like IDMC ids
NAME = "p_SB_MP_Atender"
PROJECT_DIR = "Explore/Rest Accelerator"
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def opt_ref(ref, objectlist=False):
    multi = '\n                     <option hide="true" name="multiSelect">true</option>' if objectlist else ""
    return f"""<options>
                     <option name="referenceTo">$po:{ref}</option>{multi}
                     <option name="required">false</option>
                     <option name="isCopy">true</option>
                  </options>"""


def str_field(name, desc=""):
    return f"""<field description="{desc}" name="{name}" type="string">
                  <options><option name="required">false</option></options>
               </field>"""


def qp(pairs):
    items = "".join(f"&lt;queryParams&gt;&lt;value&gt;{v}&lt;/value&gt;&lt;name&gt;{k}&lt;/name&gt;&lt;/queryParams&gt;" for k, v in pairs)
    return f"&lt;DataMarketplaceQueryParameters&gt;{items}&lt;/DataMarketplaceQueryParameters&gt;"


# XQuery regex: first order in the (APPROVED-filtered) list. Within an order object the
# API serialises ... "requestedProvisionedTargetRef", ..., "status", "id" ... (see ORD-4 response).
RX_ID = r'^.*?"status"\s*:\s*"APPROVED"\s*,\s*"id"\s*:\s*"([^"]+)".*$'
RX_TARGET = r'^.*?"requestedProvisionedTargetRef"\s*:\s*"([^"]+)".*$'

process = f"""<process xmlns="http://schemas.active-endpoints.com/appmodules/screenflow/2010/10/avosScreenflow.xsd"
                  xmlns:tfm="http://schemas.active-endpoints.com/appmodules/screenflow/2021/04/taskflowModel.xsd"
                  xmlns:list="urn:activevos:spi:list:functions"
                  GUID="{GUID}"
                  displayName="{NAME}"
                  name="{NAME}"
                  overrideAPIName="false">
            <parameterSet xmlns="http://schemas.active-endpoints.com/appmodules/screenflow/2021/04/taskflowModel.xsd"/>
            <appliesTo/>
            <description>Demo SB C08-AE-07: atiende el primer pedido APROBADO de DCL-4 (Snowflake stub + fulfill).</description>
            <tags/>
            <generator>Informatica Process Designer 11</generator>
            <output>
               <field description="Resultado de la ejecucion" name="resultado" type="string">
                  <options><option name="required">false</option></options>
               </field>
            </output>
            <tempFields>
               <field description="" name="Temp_Query_Params" type="objectlist">
                  {opt_ref('DataMarketplaceQueryParameters', True)}
               </field>
               <field description="" name="Temp_Path_Params" type="objectlist">
                  {opt_ref('DataMarketplacePathVariables', True)}
               </field>
               {str_field('Temp_Body', 'Payload JSON enviado al servicio')}
               {str_field('Temp_Response')}
               {str_field('Temp_OrderId')}
               {str_field('Temp_TargetId')}
               {str_field('Temp_Snowflake_SQL', 'SQL que se ejecutara en Snowflake (stub)')}
               <field description="1 = hay pedido aprobado" name="Temp_Hay_Pedido" type="int">
                  <options><option name="required">false</option></options>
               </field>
            </tempFields>
            <notes>Ejecutar por agenda (cada 5 min). Cada ejecucion atiende un pedido. Paso Snowflake = stub hasta la cuenta nueva.</notes>
            <deployment skipIfRunning="true" suspendOnFault="false" tracingLevel="verbose">
               <rest>
                  <wholePayload outputWholePayload="false"/>
               </rest>
            </deployment>
            <extData>
               <nvpair name="treatEmptyStringAsNotNull">false</nvpair>
               <nvpair name="treatEmptyStringAsNull">true</nvpair>
               <nvpair name="treatEmptyObjectListAsArray">true</nvpair>
               <nvpair name="treatEmptyObjectListAsNotArray">false</nvpair>
            </extData>
            <flow id="fSBat0000000000000001">
               <start id="sSBat0000000000000001">
                  <link id="lSBat0000000000000001" targetId="aSBatPrepConsulta"/>
               </start>
               <assignment id="aSBatPrepConsulta">
                  <title>Preparar consulta pedidos aprobados</title>
                  <operation source="formula" to="temp.Temp_Query_Params">
                     <expression language="XQuery">{qp([('dataCollectionIds', DCL), ('status', 'APPROVED')])}</expression>
                  </operation>
                  <operation source="formula" to="temp.Temp_Path_Params">
                     <expression language="XQuery">&lt;DataMarketplacePathVariables/&gt;</expression>
                  </operation>
                  <operation source="formula" to="temp.Temp_Body">
                     <expression language="XQuery">'{{}}'</expression>
                  </operation>
                  <link id="lSBat0000000000000002" targetId="vSBatListarPedidos"/>
               </assignment>
               <service id="vSBatListarPedidos">
                  <title>Listar pedidos aprobados</title>
                  <serviceName>ICSExecuteCDMPApi</serviceName>
                  <serviceGUID/>
                  <serviceInput>
                     <parameter name="httpMethod" source="constant">GET</parameter>
                     <parameter name="relativePath" source="constant">orders</parameter>
                     <parameter name="payload" source="field">temp.Temp_Body</parameter>
                     <parameter name="queryParameters" source="field">temp.Temp_Query_Params</parameter>
                     <parameter name="pathVariables" source="field">temp.Temp_Path_Params</parameter>
                  </serviceInput>
                  <link id="lSBat0000000000000003" targetId="aSBatExtraer"/>
               </service>
               <assignment id="aSBatExtraer">
                  <title>Extraer pedido y destino</title>
                  <operation source="field" to="temp.Temp_Response">output.Data Marketplace Response</operation>
                  <operation source="formula" to="temp.Temp_Hay_Pedido">
                     <expression language="XQuery">if (matches(string($temp.Temp_Response), '"status"\\s*:\\s*"APPROVED"\\s*,\\s*"id"\\s*:\\s*"[^"]+"', 's')) then 1 else 0</expression>
                  </operation>
                  <operation source="formula" to="temp.Temp_OrderId">
                     <expression language="XQuery">if (matches(string($temp.Temp_Response), '"status"\\s*:\\s*"APPROVED"\\s*,\\s*"id"\\s*:\\s*"[^"]+"', 's')) then replace(string($temp.Temp_Response), '{RX_ID}', '$1', 's') else ''</expression>
                  </operation>
                  <operation source="formula" to="temp.Temp_TargetId">
                     <expression language="XQuery">if (matches(string($temp.Temp_Response), '"requestedProvisionedTargetRef"\\s*:\\s*"[^"]+"', 's')) then replace(string($temp.Temp_Response), '{RX_TARGET}', '$1', 's') else ''</expression>
                  </operation>
                  <link id="lSBat0000000000000004" targetId="aSBatSnowflake"/>
               </assignment>
                     <assignment id="aSBatSnowflake">
                        <title>Snowflake STUB (bloque A script 05)</title>
                        <operation source="formula" to="temp.Temp_Snowflake_SQL">
                           <expression language="XQuery">concat('CREATE USER IF NOT EXISTS EXT_ANALISTA_PYME ... DAYS_TO_EXPIRY=1 COMMENT=''Marketplace order ', $temp.Temp_OrderId, '''; GRANT ROLE FR_EXTERNAL_READER TO USER EXT_ANALISTA_PYME;')</expression>
                        </operation>
                        <operation source="formula" to="temp.Temp_Query_Params">
                           <expression language="XQuery">&lt;DataMarketplaceQueryParameters&gt;&lt;queryParams&gt;&lt;value&gt;{{$temp.Temp_TargetId}}&lt;/value&gt;&lt;name&gt;deliveryTargetId&lt;/name&gt;&lt;/queryParams&gt;&lt;queryParams&gt;&lt;value&gt;Acceso entregado automaticamente por CAI (usuario temporal Snowflake, 24 h)&lt;/value&gt;&lt;name&gt;comment&lt;/name&gt;&lt;/queryParams&gt;&lt;/DataMarketplaceQueryParameters&gt;</expression>
                        </operation>
                        <operation source="formula" to="temp.Temp_Path_Params">
                           <expression language="XQuery">&lt;DataMarketplacePathVariables&gt;&lt;pathVariables&gt;&lt;value&gt;{{$temp.Temp_OrderId}}&lt;/value&gt;&lt;name&gt;orderId&lt;/name&gt;&lt;/pathVariables&gt;&lt;/DataMarketplacePathVariables&gt;</expression>
                        </operation>
                  <operation source="formula" to="temp.Temp_Body">
                     <expression language="XQuery">'{{}}'</expression>
                  </operation>
                        <link id="lSBat0000000000000005" targetId="cSBatHayPedido"/>
                     </assignment>
               <container id="cSBatHayPedido" type="exclusive">
                  <title>Hay pedido aprobado?</title>
                  <flow id="fSBatSi">
                     <service id="vSBatFulfill">
                        <title>Fulfill pedido</title>
                        <serviceName>ICSExecuteCDMPApi</serviceName>
                        <serviceGUID/>
                        <serviceInput>
                           <parameter name="httpMethod" source="constant">PUT</parameter>
                           <parameter name="relativePath" source="constant">orders/{{{{orderId}}}}/fulfill</parameter>
                     <parameter name="payload" source="field">temp.Temp_Body</parameter>
                           <parameter name="queryParameters" source="field">temp.Temp_Query_Params</parameter>
                           <parameter name="pathVariables" source="field">temp.Temp_Path_Params</parameter>
                        </serviceInput>
                        <link id="lSBat0000000000000006" targetId="aSBatSalidaSi"/>
                     </service>
                     <assignment id="aSBatSalidaSi">
                        <title>Resultado atendido</title>
                        <operation source="formula" to="output.resultado">
                           <expression language="XQuery">concat('Pedido ', $temp.Temp_OrderId, ' atendido (destino ', $temp.Temp_TargetId, '). Snowflake STUB: ', $temp.Temp_Snowflake_SQL)</expression>
                        </operation>
                     </assignment>
                     <link id="lSBat0000000000000007" targetId="cSBatHayPedido" type="containerLink"/>
                  </flow>
                  <flow id="fSBatNo">
                     <assignment id="aSBatSalidaNo">
                        <title>Sin pedidos</title>
                        <operation source="formula" to="output.resultado">
                           <expression language="XQuery">'Sin pedidos aprobados pendientes en DCL-4'</expression>
                        </operation>
                     </assignment>
                     <link id="lSBat0000000000000008" targetId="cSBatHayPedido" type="containerLink"/>
                  </flow>
                  <link id="lSBat0000000000000009" targetId="fSBatSi" type="containerLink">
                     <condition source="formula">
                        <function name="equals">
                           <arg name="left">{{$temp.Temp_Hay_Pedido}}</arg>
                           <arg name="right">{{1}}</arg>
                        </function>
                     </condition>
                  </link>
                  <link id="lSBat0000000000000010" targetId="fSBatNo" type="containerLink"/>
                  <link id="lSBat0000000000000011" targetId="eSBatEnd"/>
               </container>
               <end id="eSBatEnd">
                  <title>End</title>
               </end>
            </flow>
         </process>"""

doc = f"""<aetgt:getResponse xmlns:aetgt="http://schemas.active-endpoints.com/appmodules/repository/2010/10/avrepository.xsd"
                   xmlns:types1="http://schemas.active-endpoints.com/appmodules/repository/2010/10/avrepository.xsd">
   <types1:Item>
      <types1:EntryId>{GUID}::pd.xml</types1:EntryId>
      <types1:Name>{NAME}</types1:Name>
      <types1:MimeType>application/xml+process</types1:MimeType>
      <types1:Description>Demo SB C08-AE-07: fulfill automatico de pedidos aprobados.</types1:Description>
      <types1:AppliesTo/>
      <types1:Tags/>
      <types1:VersionLabel>1.0</types1:VersionLabel>
      <types1:State>CURRENT</types1:State>
      <types1:ProcessGroup/>
      <types1:CreationDate>{NOW}</types1:CreationDate>
      <types1:ModificationDate>{NOW}</types1:ModificationDate>
      <types1:PublicationStatus>unpublished</types1:PublicationStatus>
      <types1:Entry>
         {process}
      </types1:Entry>
      <types1:GUID>{GUID}</types1:GUID>
      <types1:DisplayName>{NAME}</types1:DisplayName>
   </types1:Item>
   <types1:CurrentServerDateTime>{NOW}</types1:CurrentServerDateTime>
</aetgt:getResponse>
"""

meta = json.load(open(os.path.join(SRC, "exportMetadata.v2.json")))
proj = next(o for o in meta["exportedObjects"] if o["objectType"] == "Project")
meta["name"] = NAME
meta["exportedObjects"] = [{
    "objectGuid": GUID, "objectName": NAME, "objectType": "PROCESS", "path": "/" + PROJECT_DIR,
    "metadata": {"modelVersion": {"major": 1, "minor": 0}, "repoInfo": {"repoHandle": f"{GUID}::pd.xml"},
                 "objectRefs": [], "contextAttributes": None,
                 "additionalInfo": {"description": "Demo SB C08-AE-07", "contentType": "application/json; charset=utf-8",
                                    "documentState": "VALID"}}}, proj]

stage = OUT + ".d"
shutil.rmtree(stage, ignore_errors=True)
os.makedirs(os.path.join(stage, PROJECT_DIR))
files = {
    f"{PROJECT_DIR}/{NAME}.PROCESS.xml": doc.encode(),
    "Explore/Rest Accelerator.Project.json": open(os.path.join(SRC, "Explore/Rest Accelerator.Project.json"), "rb").read(),
    "exportMetadata.v2.json": json.dumps(meta, indent=2).encode(),
}
csv = f"objectPath,objectName,objectType,id\n/{PROJECT_DIR},{NAME},PROCESS,{GUID}\n/Explore,Rest Accelerator,Project,{proj['objectGuid']}\n"
files[f"ContentsofExportPackage_{NAME}.csv"] = csv.encode()
chk = "#\n#" + datetime.now(timezone.utc).strftime("%a %b %d %H:%M:%S UTC %Y") + "\n"
for k in ("exportMetadata.v2.json", f"{PROJECT_DIR}/{NAME}.PROCESS.xml", "Explore/Rest Accelerator.Project.json"):
    chk += k.replace(" ", "\\ ") + "=" + hashlib.sha256(files[k]).hexdigest().upper() + "\n"
files["exportPackage.chksum"] = chk.encode()

with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    for k, v in files.items():
        z.writestr(k, v)
print("ok", OUT)
