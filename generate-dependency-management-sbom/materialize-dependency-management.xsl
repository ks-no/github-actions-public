<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:pom="http://maven.apache.org/POM/4.0.0"
                xmlns="http://maven.apache.org/POM/4.0.0"
                exclude-result-prefixes="pom">

    <xsl:output method="xml" indent="yes" encoding="UTF-8"/>

    <xsl:param name="sbomGroupId" select="'no.ks.fiks.sbom'"/>
    <xsl:param name="sbomArtifactId" select="'dependency-management-sbom'"/>

    <!-- Nøkkel for å dedupe på groupId:artifactId:classifier. Klassifikator
         er med i nøkkelen fordi enkelte artefakter kun finnes som flere
         klassifiserte varianter i dependencyManagement, uten noen
         uklassifisert fallback - dedupe på bare groupId:artifactId ville da
         mistet alle unntatt den første klassifiserte varianten. Ekte
         scope=import-BOM-markører overlever ikke Mavens model-merge (de er
         borte fra effective-pom, innholdet er allerede flatet ut i stedet) -
         filteret her er bare et forsvarsnett i tilfelle det skulle dukke opp
         likevel. type=pom er IKKE filtrert bort: det kan være ekte
         artefakter (f.eks. kotlin-stdlib-common), ikke BOM-markører. -->
    <xsl:key name="dep-by-gac"
             match="pom:dependencyManagement/pom:dependencies/pom:dependency[not(pom:scope='import')]"
             use="concat(pom:groupId, ':', pom:artifactId, ':', pom:classifier)"/>

    <xsl:template match="/pom:project">
        <project>
            <modelVersion>4.0.0</modelVersion>
            <groupId><xsl:value-of select="$sbomGroupId"/></groupId>
            <artifactId><xsl:value-of select="$sbomArtifactId"/></artifactId>
            <version>0-SBOM</version>
            <packaging>pom</packaging>

            <!-- Entriene legges OGSÅ i dependencyManagement, ikke bare
                 dependencies: uten den beholder ikke de materialiserte
                 versjonene pin-status. Et transitivt artefakt kan trekke inn
                 samme groupId:artifactId gjennom sin EGEN (arvede)
                 dependencyManagement som et versjonsspenn - konkurrerer den
                 bare som en vanlig <dependency> uten dependencyManagement,
                 kan Mavens mediation velge spennet fremfor pin-en selv om
                 pin-en er nærmere i treet. Et nedstrøms-prosjekt som arver
                 konsument-pom-en direkte rammes ikke av dette, siden
                 dependencyManagement der alltid er nærmest og vinner
                 uansett - duplisert dependencyManagement her gjenoppretter
                 samme overstyrings-semantikk for SBOM-byggets egen
                 resolvering. -->
            <dependencyManagement>
                <dependencies>
                    <xsl:apply-templates select="
                        pom:dependencyManagement/pom:dependencies/pom:dependency
                        [not(pom:scope='import')]
                        [generate-id() = generate-id(key('dep-by-gac', concat(pom:groupId, ':', pom:artifactId, ':', pom:classifier))[1])]"/>
                </dependencies>
            </dependencyManagement>

            <dependencies>
                <!-- kun første treff per groupId:artifactId:classifier -->
                <xsl:apply-templates select="
                    pom:dependencyManagement/pom:dependencies/pom:dependency
                    [not(pom:scope='import')]
                    [generate-id() = generate-id(key('dep-by-gac', concat(pom:groupId, ':', pom:artifactId, ':', pom:classifier))[1])]"/>
            </dependencies>
        </project>
    </xsl:template>

    <!-- én managed dependency -> én reell dependency. type og classifier må
         være med der de finnes, ellers matcher den materialiserte
         dependencyManagement-entryen ikke den reelle avhengigheten (og
         Maven finner ingen versjon for den). -->
    <xsl:template match="pom:dependency">
        <dependency>
            <groupId><xsl:value-of select="pom:groupId"/></groupId>
            <artifactId><xsl:value-of select="pom:artifactId"/></artifactId>
            <version><xsl:value-of select="pom:version"/></version>
            <xsl:if test="pom:type and pom:type != 'jar'">
                <type><xsl:value-of select="pom:type"/></type>
            </xsl:if>
            <xsl:if test="pom:classifier">
                <classifier><xsl:value-of select="pom:classifier"/></classifier>
            </xsl:if>
        </dependency>
    </xsl:template>

</xsl:stylesheet>
