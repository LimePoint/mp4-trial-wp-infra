<?xml version="1.0" encoding="ISO-8859-1"?>

<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="3.0">
	<xsl:output method="html"/>
	
	<xsl:output omit-xml-declaration="yes" indent="yes"/>
	<xsl:strip-space elements="*"/>
	
	<xsl:template match="/">
		<html>
			
			<style>
				table {
					border: 3px black;
					border-collapse: collapse;
				}
				th {
					background-color: #4CAF50;
					color: black;
				}
				th, td {
					border-bottom: 1px solid #ddd;
					padding: 10px;
				}
				tr:hover {
					background-color: #d2f7a5;
				}
			
			</style>
			<body>
				<h2>OBP Friendly URLs</h2>
				<table>
					<tr align="left">
						<th>Application</th>
						<th>URL</th>
					</tr>
					<xsl:apply-templates select="/config/obpobu" mode="friendly"/>
					<xsl:apply-templates select="/config/obpsoa" mode="friendly"/>
					<xsl:apply-templates select="/config/obpbip" mode="friendly"/>
					<xsl:apply-templates select="/config/obpipm" mode="friendly"/>
					<xsl:apply-templates select="/config/obpdoc" mode="friendly"/>
				</table>
				
				<hr></hr>
				<h2>LDAP Details</h2>
				<xsl:apply-templates select="/config/obpoid" mode="ldap"/>
				<xsl:apply-templates select="/config/obpcid" mode="ldap"/>
				
				<hr></hr>
				<h2>Weblogic Details</h2>
				<xsl:apply-templates select="/config/*[wls_domain_name]" mode="url"/>
				
				<hr></hr>
				<h2>Database Connection Details</h2>
				<table>
					<col width="5%" />
					<col width="15%" />
					<tr align="left">
						<th>Asset</th>
						<th>Database</th>
						<th>Port</th>
						<th>Service</th>
						<th>RCU Prefix</th>
						<th>JDBC String</th>
					</tr>
					<xsl:apply-templates select="/config/*/database"/>
				</table>
			
			</body>
		</html>
	</xsl:template>
	
	<xsl:template match="/config/*/database">
		<xsl:if test="../name() != 'ofsodi' and ../name() != 'ofswls' and ../name() != 'ofsofp'">
			<tr align="left">
				<td>
					<xsl:value-of select="../name()"/>
				</td>
				<td>
					<xsl:value-of select="scan_address"/>
				</td>
				<td>
					<xsl:value-of select="listen_port"/>
				</td>
				<td>
					<xsl:value-of select="service_name"/>
				</td>
				<td>
					<xsl:value-of select="rcu_schema_prefix"/>
				</td>
				<td>
					<xsl:value-of select="concat('jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=', scan_address, ')(PORT=', listen_port, '))(CONNECT_DATA=(SERVICE_NAME=', service_name ,')))' ) "/>
				</td>
			</tr>
		</xsl:if>
		
	</xsl:template>
	
	<xsl:template match="obpobu" mode="friendly">
		<tr>
			<td>Oracle Banker Login</td>
			<xsl:variable name="hyperlink"
			              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/friendly_port,'/com.ofss.fc.ui.view/faces/main.jspx')"/>
			<td>
				<a href="{$hyperlink}" target="_blank">
					<xsl:copy-of select="$hyperlink"/>
				</a>
			</td>
		</tr>
		<tr>
			<td>Oracle Banker Application Tracker</td>
			<xsl:variable name="hyperlink"
			              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/friendly_port,'/com.ofss.fc.ui.view.obeo/faces/applicationTracker.jspx')"/>
			<td>
				<a href="{$hyperlink}" target="_blank">
					<xsl:copy-of select="$hyperlink"/>
				</a>
			</td>
		</tr>
	</xsl:template>
	
	<xsl:template match="obpsoa" mode="friendly">
		<tr>
			<td>Oracle Worklist Integration</td>
			<xsl:variable name="hyperlink"
			              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/friendly_port,'/integration/worklistapp')"/>
			<td>
				<a href="{$hyperlink}" target="_blank">
					<xsl:copy-of select="$hyperlink"/>
				</a>
			</td>
		</tr>
	</xsl:template>
	
	<xsl:template match="obpbip" mode="friendly">
		<tr>
			<td>Oracle Business Intelligence Publisher</td>
			<xsl:variable name="hyperlink"
			              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/friendly_port,'/xmlpserver')"/>
			<td>
				<a href="{$hyperlink}" target="_blank">
					<xsl:copy-of select="$hyperlink"/>
				</a>
			</td>
		</tr>
		<tr>
			<td>Oracle Analytics</td>
			<xsl:variable name="hyperlink"
			              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/friendly_port,'/analytics')"/>
			<td>
				<a href="{$hyperlink}" target="_blank">
					<xsl:copy-of select="$hyperlink"/>
				</a>
			</td>
		</tr>
	</xsl:template>
	
	<xsl:template match="obpipm" mode="friendly">
		<tr>
			<td>Oracle Imaging</td>
			<xsl:variable name="hyperlink" select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/ipm_port,'/imaging')"/>
			<td>
				<a href="{$hyperlink}" target="_blank">
					<xsl:copy-of select="$hyperlink"/>
				</a>
			</td>
		</tr>
		<tr>
			<td>Oracle Content Server</td>
			<xsl:variable name="hyperlink" select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/ucm_port,'/cs')"/>
			<td>
				<a href="{$hyperlink}" target="_blank">
					<xsl:copy-of select="$hyperlink"/>
				</a>
			</td>
		</tr>
	</xsl:template>
	
	<xsl:template match="obpdoc" mode="friendly">
		<tr>
			<td>Oracle Documaker Correspondence</td>
			<xsl:variable name="hyperlink"
			              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/idm_port,'/DocumakerCorrespondence')"/>
			<td>
				<a href="{$hyperlink}" target="_blank">
					<xsl:copy-of select="$hyperlink"/>
				</a>
			</td>
		</tr>
	</xsl:template>
	
	<xsl:template match="/config/obpobu" mode="url">
		<h3>OBP UI</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Banker Login</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/friendly_port,'/com.ofss.fc.ui.view/faces/main.jspx')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpbip" mode="url">
		<h3>OBP Business Intelligence</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Analytics</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/friendly_port,'/analytics')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Business Intelligence Publisher</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/friendly_port,'/xmlpserver')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpdoc" mode="url">
		<h3>OBP Documaker</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Documaker Admin Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/dmkr_port,'/DocumakerAdministrator')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Documaker Correspondence</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/idm_port,'/DocumakerCorrespondence')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpidm" mode="url">
		<h3>OBP ODSM</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle ODSM</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/odsm')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpipm" mode="url">
		<h3>OBP Imaging</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Imaging</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/ipm_port,'/imaging')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Content Server</td>
				<xsl:variable name="hyperlink" select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/ucm_port,'/cs')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpoam" mode="url">
		<h3>OBP Access Manager</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Access Manager Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/oamconsole')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpobh" mode="url">
		<h3>OBP Host</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpodi" mode="url">
		<h3>OBP Data Integrator (ODI)</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle ODI Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/odi_port,'/odiconsole')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpsoa" mode="url">
		<h3>OBP SOA</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Worklist Integration</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/friendly_name,':',frontend/ht_port,'/integration/worklistapp')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle SOA Infra</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/soa_port,'/soa-infra')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obposb" mode="url">
		<h3>OBP Service Bus</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/osbconsole')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpotd" mode="url">
		<!--<h3>OTD Oracle Traffic Director</h3>-->
		<!--<table>-->
			<!--<xsl:apply-templates select="hostnameList" mode="hosts"/>-->
			<!--<tr>-->
				<!--<td>Oracle Weblogic Administration Console</td>-->
				<!--<xsl:variable name="hyperlink"-->
				              <!--select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>-->
				<!--<td>-->
					<!--<a href="{$hyperlink}" target="_blank">-->
						<!--<xsl:copy-of select="$hyperlink"/>-->
					<!--</a>-->
				<!--</td>-->
			<!--</tr>-->
			<!--<tr>-->
				<!--<td>Oracle Fusion Middleware Control Console</td>-->
				<!--<xsl:variable name="hyperlink"-->
				              <!--select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>-->
				<!--<td>-->
					<!--<a href="{$hyperlink}" target="_blank">-->
						<!--<xsl:copy-of select="$hyperlink"/>-->
					<!--</a>-->
				<!--</td>-->
			<!--</tr>-->
		<!--</table>-->
	</xsl:template>
	
	<xsl:template match="obpoid" mode="ldap">
		<h3>OBP Oracle Internal Directory (OID)</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			<tr>
				<td>LDAP Server Details</td>
				<xsl:variable name="hyperlink"
				              select="concat('ldaps://',frontend/managed_host,':',frontend/ldap_port)"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Replication Server Details</td>
				<xsl:variable name="hyperlink"
				              select="concat('ldaps://',frontend/managed_host,':',frontend/repl_port)"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpcid" mode="ldap">
		<h3>OBP Oracle Customer Directory (OID)</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			<tr>
				<td>LDAP Server Details</td>
				<xsl:variable name="hyperlink"
				              select="concat('ldaps://',frontend/managed_host,':',frontend/ldap_port)"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Replication Server Details</td>
				<xsl:variable name="hyperlink"
				              select="concat('ldaps://',frontend/managed_host,':',frontend/repl_port)"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpoim" mode="url">
		<h3>Staff Identity Manager (OIM)</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Sysadmin Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/oim_port,'/sysadmin')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Identity Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/oim_port,'/identity')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Business Intelligence Publisher</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/bi_port,'/xmlpserver')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle SOA Infra</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/soa_port,'/soa-infra')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/obpcim" mode="url">
		<h3>Customer Identity Manager (OIM)</h3>
		<table>
			<tr align="left">
				<th>Item</th>
				<th>Value</th>
			</tr>
			<xsl:apply-templates select="hostnameList" mode="hosts"/>
			<tr>
				<td>Oracle Weblogic Administration Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Fusion Middleware Control Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Sysadmin Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/oim_port,'/sysadmin')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Identity Console</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/oim_port,'/identity')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle Business Intelligence Publisher</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/bi_port,'/xmlpserver')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
			<tr>
				<td>Oracle SOA Infra</td>
				<xsl:variable name="hyperlink"
				              select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/soa_port,'/soa-infra')"/>
				<td>
					<a href="{$hyperlink}" target="_blank">
						<xsl:copy-of select="$hyperlink"/>
					</a>
				</td>
			</tr>
		</table>
	</xsl:template>
	
	<xsl:template match="/config/ofsodi" mode="url">
		<!--<h3>OFSAA Data Integrator (ODI)</h3>-->
		<!--<table>-->
		<!--<tr align="left">-->
			<!--<th>Item</th>-->
			<!--<th>Value</th>-->
		<!--</tr>-->
			<!--<xsl:apply-templates select="hostnameList" mode="hosts"/>-->
			<!---->
			<!--<tr>-->
				<!--<td>Oracle Weblogic Administration Console</td>-->
				<!--<xsl:variable name="hyperlink"-->
				              <!--select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>-->
				<!--<td>-->
					<!--<a href="{$hyperlink}" target="_blank">-->
						<!--<xsl:copy-of select="$hyperlink"/>-->
					<!--</a>-->
				<!--</td>-->
			<!--</tr>-->
			<!--<tr>-->
				<!--<td>Oracle Fusion Middleware Control Console</td>-->
				<!--<xsl:variable name="hyperlink"-->
				              <!--select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>-->
				<!--<td>-->
					<!--<a href="{$hyperlink}" target="_blank">-->
						<!--<xsl:copy-of select="$hyperlink"/>-->
					<!--</a>-->
				<!--</td>-->
			<!--</tr>-->
			<!--<tr>-->
				<!--<td>Oracle ODI Console</td>-->
				<!--<xsl:variable name="hyperlink"-->
				              <!--select="concat(frontend/protocol,'://',frontend/otd_vip_name,':',frontend/odi_port,'/odiconsole')"/>-->
				<!--<td>-->
					<!--<a href="{$hyperlink}" target="_blank">-->
						<!--<xsl:copy-of select="$hyperlink"/>-->
					<!--</a>-->
				<!--</td>-->
			<!--</tr>-->
		<!--</table>-->
	</xsl:template>
	
	<xsl:template match="/config/ofswls" mode="url">
		<!--<h3>OFSAA Web Server</h3>-->
		<!--<table>-->
		<!--<tr align="left">-->
			<!--<th>Item</th>-->
			<!--<th>Value</th>-->
		<!--</tr>-->
			<!--<xsl:apply-templates select="hostnameList" mode="hosts"/>-->
			<!---->
			<!--<tr>-->
				<!--<td>Oracle Weblogic Administration Console</td>-->
				<!--<xsl:variable name="hyperlink"-->
				              <!--select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/console')"/>-->
				<!--<td>-->
					<!--<a href="{$hyperlink}" target="_blank">-->
						<!--<xsl:copy-of select="$hyperlink"/>-->
					<!--</a>-->
				<!--</td>-->
			<!--</tr>-->
			<!--<tr>-->
				<!--<td>Oracle Fusion Middleware Control Console</td>-->
				<!--<xsl:variable name="hyperlink"-->
				              <!--select="concat(frontend/protocol,'://',frontend/admin_host,':',frontend/admin_port,'/em')"/>-->
				<!--<td>-->
					<!--<a href="{$hyperlink}" target="_blank">-->
						<!--<xsl:copy-of select="$hyperlink"/>-->
					<!--</a>-->
				<!--</td>-->
			<!--</tr>-->
			<!--<tr>-->
				<!--<td>OFSAA Login URL</td>-->
				<!--<xsl:variable name="hyperlink" select="concat(frontend/ofsaa_wls_address,'/ofsaa')"/>-->
				<!--<td>-->
					<!--<a href="{$hyperlink}" target="_blank">-->
						<!--<xsl:copy-of select="$hyperlink"/>-->
					<!--</a>-->
				<!--</td>-->
			<!--</tr>-->
		<!--</table>-->
	</xsl:template>
	
	<xsl:template match="hostnameList" mode="hosts">
		<tr>
			<td>Hosts</td>
			<td>
				<xsl:variable name="domain" select="../dns_domain_name"/>
				<xsl:variable name="hosts" select="tokenize(.,'obp')"/>
				<xsl:for-each select="$hosts">
					<xsl:if test="position() != 1">
						<xsl:value-of select="concat('obp',.,$domain)"/>
						<br/>
					</xsl:if>
				</xsl:for-each>
			</td>
		</tr>
	</xsl:template>
	
	<xsl:template match="/config/id">
		#
		<xsl:value-of select="."/>
	</xsl:template>
	
	<xsl:template match="text()"/>

</xsl:stylesheet>


